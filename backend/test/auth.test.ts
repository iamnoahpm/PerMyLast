import { beforeEach, describe, expect, it } from "vitest";
import { config } from "../config.ts";
import { handleRequest } from "../src/app.ts";
import type { Deps } from "../src/env.ts";
import { b64urlEncode, clearJwksCache, sha256Hex, signJwt, verifyJwt } from "../src/jwt.ts";
import { testEnv } from "./helpers.ts";

const enc = new TextEncoder();
const NOW = Date.UTC(2026, 9, 22, 12);
const secs = (ms: number) => Math.floor(ms / 1000);

// A throwaway RSA key pair stands in for Apple's and Google's signing keys.
const pair = (await crypto.subtle.generateKey(
  { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
const jwk = { ...(await crypto.subtle.exportKey("jwk", pair.publicKey)), kid: "test-kid" };

async function idToken(claims: Record<string, unknown>, kid = "test-kid"): Promise<string> {
  const part = (v: unknown) => b64urlEncode(enc.encode(JSON.stringify(v)));
  const body = `${part({ alg: "RS256", kid })}.${part(claims)}`;
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", pair.privateKey, enc.encode(body));
  return `${body}.${b64urlEncode(sig)}`;
}

let jwksFetches = 0;
const deps: Deps = {
  now: () => NOW,
  sendEmail: async () => {},
  fetch: (async () => { jwksFetches++; return Response.json({ keys: [jwk] }); }) as unknown as typeof fetch,
};

const apple = (o: Record<string, unknown> = {}) => ({
  iss: "https://appleid.apple.com", aud: "app.permylast", sub: "apple-001", exp: secs(NOW) + 600,
  email: "Noah@Example.com", email_verified: "true", ...o,
});
const google = (o: Record<string, unknown> = {}) => ({
  iss: "https://accounts.google.com", aud: "test-google-client", sub: "google-001", exp: secs(NOW) + 600,
  email: "noah@example.com", email_verified: true, ...o,
});

const post = (path: string, body: unknown) =>
  handleRequest(new Request(`https://api.test${path}`, { method: "POST", body: JSON.stringify(body) }), testEnv, deps);

beforeEach(() => { clearJwksCache(); jwksFetches = 0; });

describe("session tokens", () => {
  it("round-trips, and rejects tampering, expiry and other algorithms", async () => {
    const t = await signJwt({ sub: "u1", exp: secs(NOW) + 60 }, "secret");
    expect((await verifyJwt(t, "secret", NOW)).sub).toBe("u1");
    await expect(verifyJwt(t, "other-secret", NOW)).rejects.toThrow();
    await expect(verifyJwt(t, "secret", NOW + 61_000)).rejects.toThrow("expired");
    const [h, , s] = t.split(".");
    const forged = `${h}.${b64urlEncode(enc.encode(JSON.stringify({ sub: "admin", exp: secs(NOW) + 60 })))}.${s}`;
    await expect(verifyJwt(forged, "secret", NOW)).rejects.toThrow();
    const none = `${b64urlEncode(enc.encode('{"alg":"none"}'))}.${b64urlEncode(enc.encode('{"sub":"u1","exp":9999999999}'))}.`;
    await expect(verifyJwt(none, "secret", NOW)).rejects.toThrow();
  });
});

describe("Sign in with Apple / Google", () => {
  it("creates an account, a profile, and a working session", async () => {
    const res = await post("/v1/auth/apple", { id_token: await idToken(apple()) });
    expect(res.status).toBe(200);
    const s = await res.json<{ user_id: string; access_token: string; refresh_token: string; expires_in: number }>();
    expect(s.expires_in).toBe(config.ACCESS_TOKEN_TTL_S);
    expect((await verifyJwt(s.access_token, testEnv.JWT_SECRET, NOW)).sub).toBe(s.user_id);
    expect(await testEnv.DB.prepare("SELECT 1 FROM profiles WHERE user_id = ?").bind(s.user_id).first()).not.toBeNull();
    const me = await handleRequest(new Request("https://api.test/v1/me", { headers: { authorization: `Bearer ${s.access_token}` } }), testEnv, deps);
    expect((await me.json<{ plan: string }>()).plan).toBe("none");
  });

  it("signing in again returns the same account; the verified email links Google to it", async () => {
    const a = await (await post("/v1/auth/apple", { id_token: await idToken(apple({ sub: "apple-link", email: "link@example.com" })) })).json<{ user_id: string }>();
    const again = await (await post("/v1/auth/apple", { id_token: await idToken(apple({ sub: "apple-link", email: "link@example.com" })) })).json<{ user_id: string }>();
    const g = await (await post("/v1/auth/google", { id_token: await idToken(google({ sub: "google-link", email: "link@example.com" })) })).json<{ user_id: string }>();
    expect(again.user_id).toBe(a.user_id);
    expect(g.user_id).toBe(a.user_id);
  });

  it("a second Apple login with an email already on another Apple account gets its own account", async () => {
    const first = await (await post("/v1/auth/apple", { id_token: await idToken(apple({ sub: "dup-1", email: "dup@example.com" })) })).json<{ user_id: string }>();
    const second = await post("/v1/auth/apple", { id_token: await idToken(apple({ sub: "dup-2", email: "dup@example.com" })) });
    expect(second.status).toBe(200);
    expect((await second.json<{ user_id: string }>()).user_id).not.toBe(first.user_id);
  });

  it("simultaneous first sign-ins end up on one account", async () => {
    const token = await idToken(apple({ sub: "race-1", email: "race@example.com" }));
    const ids = await Promise.all(Array.from({ length: 10 }, async () => (await (await post("/v1/auth/apple", { id_token: token })).json<{ user_id: string }>()).user_id));
    expect(new Set(ids).size).toBe(1);
  });

  it("does not link on an unverified email", async () => {
    const a = await (await post("/v1/auth/apple", { id_token: await idToken(apple({ sub: "apple-x", email: "x@example.com" })) })).json<{ user_id: string }>();
    const g = await (await post("/v1/auth/google", { id_token: await idToken(google({ sub: "google-x", email: "x@example.com", email_verified: false })) })).json<{ user_id: string }>();
    expect(g.user_id).not.toBe(a.user_id);
  });

  it.each([
    ["wrong audience", apple({ aud: "someone.else" })],
    ["wrong issuer", apple({ iss: "https://evil.example" })],
    ["expired", apple({ exp: secs(NOW) - 1 })],
    ["no subject", apple({ sub: "" })],
  ])("rejects a token with %s", async (_name, claims) => {
    const res = await post("/v1/auth/apple", { id_token: await idToken(claims) });
    expect(res.status).toBe(401);
    expect((await res.json<{ error: { code: string } }>()).error.code).toBe("invalid_token");
  });

  it("rejects a bad signature and an unknown key id", async () => {
    const good = await idToken(apple());
    const tampered = `${good.slice(0, -4)}AAAA`;
    expect((await post("/v1/auth/apple", { id_token: tampered })).status).toBe(401);
    expect((await post("/v1/auth/apple", { id_token: await idToken(apple(), "rotated-away") })).status).toBe(401);
  });

  it("checks Apple's nonce against the raw value the app hashed", async () => {
    const hashed = await sha256Hex("raw-nonce");
    expect((await post("/v1/auth/apple", { id_token: await idToken(apple({ sub: "n1", nonce: hashed })), nonce: "raw-nonce" })).status).toBe(200);
    expect((await post("/v1/auth/apple", { id_token: await idToken(apple({ sub: "n2", nonce: hashed })), nonce: "different" })).status).toBe(401);
    expect((await post("/v1/auth/apple", { id_token: await idToken(apple({ sub: "n3", nonce: hashed })) })).status).toBe(401);
  });

  it("caches the signing keys", async () => {
    await post("/v1/auth/apple", { id_token: await idToken(apple({ sub: "c1" })) });
    await post("/v1/auth/apple", { id_token: await idToken(apple({ sub: "c2" })) });
    expect(jwksFetches).toBe(1);
  });

  it("needs an id_token", async () => {
    expect((await post("/v1/auth/google", {})).status).toBe(400);
  });
});

describe("refresh tokens", () => {
  async function signedIn() {
    return (await post("/v1/auth/google", { id_token: await idToken(google({ sub: `g-${crypto.randomUUID()}`, email: undefined })) })).json<{ user_id: string; refresh_token: string }>();
  }

  it("rotates, stores only a hash, and treats reuse as theft", async () => {
    const s = await signedIn();
    const stored = await testEnv.DB.prepare("SELECT token_hash FROM refresh_tokens WHERE user_id = ?").bind(s.user_id).first<{ token_hash: string }>();
    expect(stored?.token_hash).not.toBe(s.refresh_token);

    const next = await post("/v1/auth/refresh", { refresh_token: s.refresh_token });
    expect(next.status).toBe(200);
    const n = await next.json<{ refresh_token: string }>();
    expect(n.refresh_token).not.toBe(s.refresh_token);

    expect((await post("/v1/auth/refresh", { refresh_token: s.refresh_token })).status).toBe(401); // reused
    expect((await post("/v1/auth/refresh", { refresh_token: n.refresh_token })).status).toBe(401); // everything revoked
  });

  it("rejects unknown and expired tokens", async () => {
    expect((await post("/v1/auth/refresh", { refresh_token: "nope" })).status).toBe(401);
    const s = await signedIn();
    const later: Deps = { ...deps, now: () => NOW + (config.REFRESH_TOKEN_TTL_S + 1) * 1000 };
    const res = await handleRequest(new Request("https://api.test/v1/auth/refresh", { method: "POST", body: JSON.stringify({ refresh_token: s.refresh_token }) }), testEnv, later);
    expect(res.status).toBe(401);
  });
});
