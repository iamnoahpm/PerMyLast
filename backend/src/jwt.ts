// Session tokens (HS256) and third-party ID token verification (RS256), on WebCrypto only.

export class AuthError extends Error {}

const enc = new TextEncoder();

export function b64urlEncode(data: ArrayBuffer | Uint8Array): string {
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function b64urlDecode(text: string): Uint8Array {
  const padded = text.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(text.length / 4) * 4, "=");
  const bin = atob(padded);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

const jsonPart = (v: unknown) => b64urlEncode(enc.encode(JSON.stringify(v)));
const parseJson = (part: string): Record<string, unknown> => {
  try {
    const v = JSON.parse(new TextDecoder().decode(b64urlDecode(part)));
    if (v && typeof v === "object") return v as Record<string, unknown>;
  } catch { /* fall through */ }
  throw new AuthError("malformed token");
};

const hmacKey = (secret: string, usage: "sign" | "verify") =>
  crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, [usage]);

export async function signJwt(claims: Record<string, unknown>, secret: string): Promise<string> {
  const body = `${jsonPart({ alg: "HS256", typ: "JWT" })}.${jsonPart(claims)}`;
  const sig = await crypto.subtle.sign("HMAC", await hmacKey(secret, "sign"), enc.encode(body));
  return `${body}.${b64urlEncode(sig)}`;
}

/** Returns the claims of a valid, unexpired HS256 token; throws AuthError otherwise. */
export async function verifyJwt(token: string, secret: string, nowMs: number): Promise<Record<string, unknown>> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new AuthError("malformed token");
  const header = parseJson(parts[0]);
  if (header.alg !== "HS256") throw new AuthError("unsupported algorithm");
  const ok = await crypto.subtle.verify("HMAC", await hmacKey(secret, "verify"), b64urlDecode(parts[2]), enc.encode(`${parts[0]}.${parts[1]}`));
  if (!ok) throw new AuthError("bad signature");
  const claims = parseJson(parts[1]);
  if (typeof claims.exp !== "number" || claims.exp * 1000 <= nowMs) throw new AuthError("token expired");
  return claims;
}

export interface IdTokenClaims {
  sub: string;
  email?: string;
  email_verified: boolean;
  nonce?: string;
}

interface Jwk { kid?: string; kty: string; n?: string; e?: string; alg?: string }
const jwksCache = new Map<string, { keys: Jwk[]; at: number }>();
const JWKS_TTL_MS = 60 * 60 * 1000;

async function loadKeys(url: string, fetcher: typeof fetch, now: number, force: boolean): Promise<Jwk[]> {
  const hit = jwksCache.get(url);
  if (hit && !force && now - hit.at < JWKS_TTL_MS) return hit.keys;
  const res = await fetcher(url);
  if (!res.ok) throw new AuthError("could not load signing keys");
  const keys = ((await res.json()) as { keys?: Jwk[] }).keys ?? [];
  jwksCache.set(url, { keys, at: now });
  return keys;
}

export function clearJwksCache(): void {
  jwksCache.clear();
}

export interface IdTokenOptions {
  jwksUrl: string;
  issuers: string[];
  audiences: string[];
  fetch: typeof fetch;
  now: number;
}

/** Verifies an Apple or Google ID token (RS256) against the provider's published keys. */
export async function verifyIdToken(token: string, opts: IdTokenOptions): Promise<IdTokenClaims> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new AuthError("malformed token");
  const header = parseJson(parts[0]);
  if (header.alg !== "RS256" || typeof header.kid !== "string") throw new AuthError("unsupported algorithm");

  let key = (await loadKeys(opts.jwksUrl, opts.fetch, opts.now, false)).find((k) => k.kid === header.kid);
  if (!key) key = (await loadKeys(opts.jwksUrl, opts.fetch, opts.now, true)).find((k) => k.kid === header.kid); // key rotation
  if (!key) throw new AuthError("unknown signing key");

  const cryptoKey = await crypto.subtle.importKey("jwk", { kty: key.kty, n: key.n, e: key.e, alg: "RS256", ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
  const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", cryptoKey, b64urlDecode(parts[2]), enc.encode(`${parts[0]}.${parts[1]}`));
  if (!ok) throw new AuthError("bad signature");

  const c = parseJson(parts[1]);
  if (typeof c.iss !== "string" || !opts.issuers.includes(c.iss)) throw new AuthError("wrong issuer");
  const aud = Array.isArray(c.aud) ? c.aud : [c.aud];
  if (!aud.some((a) => typeof a === "string" && opts.audiences.includes(a))) throw new AuthError("wrong audience");
  if (typeof c.exp !== "number" || c.exp * 1000 <= opts.now) throw new AuthError("token expired");
  if (typeof c.sub !== "string" || !c.sub) throw new AuthError("missing subject");

  return {
    sub: c.sub,
    email: typeof c.email === "string" ? c.email.toLowerCase() : undefined,
    email_verified: c.email_verified === true || c.email_verified === "true",
    nonce: typeof c.nonce === "string" ? c.nonce : undefined,
  };
}

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", enc.encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
