// Just enough X.509 to check an Apple-signed JWS: parse the fields we need, verify ECDSA chain signatures
// with WebCrypto, and pin the root. Not a general certificate library.
import { b64urlDecode } from "./jwt.ts";

interface Tlv { tag: number; start: number; valueStart: number; end: number }

function readTlv(buf: Uint8Array, offset: number): Tlv {
  const tag = buf[offset];
  let len = buf[offset + 1];
  let valueStart = offset + 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n === 0 || n > 4) throw new Error("bad DER length");
    len = 0;
    for (let i = 0; i < n; i++) len = (len << 8) | buf[offset + 2 + i];
    valueStart = offset + 2 + n;
  }
  const end = valueStart + len;
  if (end > buf.length) throw new Error("DER overruns its buffer");
  return { tag, start: offset, valueStart, end };
}

function children(buf: Uint8Array, parent: Tlv): Tlv[] {
  const out: Tlv[] = [];
  for (let p = parent.valueStart; p < parent.end;) {
    const t = readTlv(buf, p);
    out.push(t);
    p = t.end;
  }
  return out;
}

const oidString = (buf: Uint8Array, t: Tlv): string => {
  const bytes = buf.subarray(t.valueStart, t.end);
  const parts: number[] = [Math.floor(bytes[0] / 40), bytes[0] % 40];
  let v = 0;
  for (let i = 1; i < bytes.length; i++) {
    v = (v << 7) | (bytes[i] & 0x7f);
    if (!(bytes[i] & 0x80)) { parts.push(v); v = 0; }
  }
  return parts.join(".");
};

function parseTime(buf: Uint8Array, t: Tlv): number {
  const s = new TextDecoder().decode(buf.subarray(t.valueStart, t.end));
  const m = t.tag === 0x17 ? /^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(s) : /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(s);
  if (!m) throw new Error("bad certificate time");
  let year = Number(m[1]);
  if (t.tag === 0x17) year += year < 50 ? 2000 : 1900;
  return Date.UTC(year, Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]));
}

export interface Certificate {
  der: Uint8Array;
  tbs: Uint8Array;
  issuer: Uint8Array;
  subject: Uint8Array;
  spki: Uint8Array;
  curve: "P-256" | "P-384";
  notBefore: number;
  notAfter: number;
  signatureHash: "SHA-256" | "SHA-384";
  /** DER ECDSA-Sig-Value. */
  signature: Uint8Array;
  extensionOids: string[];
}

const CURVES: Record<string, "P-256" | "P-384"> = { "1.2.840.10045.3.1.7": "P-256", "1.3.132.0.34": "P-384" };
const SIG_HASH: Record<string, "SHA-256" | "SHA-384"> = { "1.2.840.10045.4.3.2": "SHA-256", "1.2.840.10045.4.3.3": "SHA-384" };

export function parseCertificate(der: Uint8Array): Certificate {
  const cert = readTlv(der, 0);
  const [tbsT, sigAlgT, sigT] = children(der, cert);
  const tbsParts = children(der, tbsT);
  let i = tbsParts[0].tag === 0xa0 ? 1 : 0; // optional version
  i += 2;                                   // serial, signature algorithm
  const issuerT = tbsParts[i++];
  const validity = children(der, tbsParts[i++]);
  const subjectT = tbsParts[i++];
  const spkiT = tbsParts[i++];

  const spkiAlg = children(der, children(der, spkiT)[0]);
  if (oidString(der, spkiAlg[0]) !== "1.2.840.10045.2.1") throw new Error("not an EC key");
  const curve = CURVES[oidString(der, spkiAlg[1])];
  const hash = SIG_HASH[oidString(der, children(der, sigAlgT)[0])];
  if (!curve || !hash) throw new Error("unsupported certificate algorithm");

  const extensionOids: string[] = [];
  const ext = tbsParts.slice(i).find((t) => t.tag === 0xa3);
  if (ext) for (const e of children(der, children(der, ext)[0])) extensionOids.push(oidString(der, children(der, e)[0]));

  return {
    der, tbs: der.subarray(tbsT.start, tbsT.end),
    issuer: der.subarray(issuerT.start, issuerT.end), subject: der.subarray(subjectT.start, subjectT.end),
    spki: der.subarray(spkiT.start, spkiT.end), curve,
    notBefore: parseTime(der, validity[0]), notAfter: parseTime(der, validity[1]),
    signatureHash: hash, signature: der.subarray(sigT.valueStart + 1, sigT.end), extensionOids,
  };
}

/** DER ECDSA-Sig-Value (SEQUENCE of two INTEGERs) to the fixed-width r||s that WebCrypto expects. */
export function derSignatureToRaw(der: Uint8Array, size: number): Uint8Array {
  const seq = readTlv(der, 0);
  const [r, s] = children(der, seq);
  const raw = new Uint8Array(size * 2);
  const put = (t: Tlv, at: number) => {
    let v = der.subarray(t.valueStart, t.end);
    while (v.length > size && v[0] === 0) v = v.subarray(1);
    if (v.length > size) throw new Error("bad ECDSA signature");
    raw.set(v, at + size - v.length);
  };
  put(r, 0);
  put(s, size);
  return raw;
}

const bytesEqual = (a: Uint8Array, b: Uint8Array) => a.length === b.length && a.every((v, i) => v === b[i]);
const toHex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");

async function verifyWithKey(spki: Uint8Array, curve: "P-256" | "P-384", hash: "SHA-256" | "SHA-384", rawSig: Uint8Array, data: Uint8Array): Promise<boolean> {
  const key = await crypto.subtle.importKey("spki", spki, { name: "ECDSA", namedCurve: curve }, false, ["verify"]);
  return crypto.subtle.verify({ name: "ECDSA", hash }, key, rawSig, data);
}

const LEAF_MARKER = "1.2.840.113635.100.6.11.1";        // Apple: receipt signing leaf
const INTERMEDIATE_MARKER = "1.2.840.113635.100.6.2.1";  // Apple: Worldwide Developer Relations intermediate

/**
 * Verifies leaf -> intermediate -> root: each certificate signed by the next, names linked, all valid at `now`,
 * the root pinned by SHA-256 fingerprint, and Apple's marker extensions present. Returns the leaf.
 */
export async function verifyAppleChain(x5c: string[], pinnedRootSha256: string[], now: number): Promise<Certificate> {
  if (x5c.length !== 3) throw new Error("unexpected certificate chain length");
  const chain = x5c.map((b64) => parseCertificate(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))));
  const [leaf, intermediate, root] = chain;

  const fingerprint = toHex(await crypto.subtle.digest("SHA-256", root.der));
  if (!pinnedRootSha256.includes(fingerprint)) throw new Error("root certificate is not trusted");
  if (!leaf.extensionOids.includes(LEAF_MARKER) || !intermediate.extensionOids.includes(INTERMEDIATE_MARKER)) throw new Error("certificate is not an Apple App Store certificate");

  for (let i = 0; i < chain.length; i++) {
    const cert = chain[i];
    const issuer = chain[Math.min(i + 1, chain.length - 1)]; // the root signs itself
    if (now < cert.notBefore || now > cert.notAfter) throw new Error("certificate is not valid now");
    if (!bytesEqual(cert.issuer, issuer.subject)) throw new Error("certificate chain is broken");
    const size = issuer.curve === "P-256" ? 32 : 48;
    if (!(await verifyWithKey(issuer.spki, issuer.curve, cert.signatureHash, derSignatureToRaw(cert.signature, size), cert.tbs))) throw new Error("certificate signature is invalid");
  }
  return leaf;
}

/** Verifies an ES256 JWS signed by the leaf certificate and returns its payload. */
export async function verifyAppleJws(jws: string, pinnedRootSha256: string[], now: number): Promise<Record<string, any>> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("malformed JWS");
  const header = JSON.parse(new TextDecoder().decode(b64urlDecode(parts[0])));
  if (header.alg !== "ES256" || !Array.isArray(header.x5c)) throw new Error("unsupported JWS");
  const leaf = await verifyAppleChain(header.x5c, pinnedRootSha256, now);
  if (leaf.curve !== "P-256") throw new Error("unexpected signing key");
  const ok = await verifyWithKey(leaf.spki, "P-256", "SHA-256", b64urlDecode(parts[2]), new TextEncoder().encode(`${parts[0]}.${parts[1]}`));
  if (!ok) throw new Error("JWS signature is invalid");
  return JSON.parse(new TextDecoder().decode(b64urlDecode(parts[1])));
}
