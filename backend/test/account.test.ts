import { describe, expect, it } from "vitest";
import { handleRequest } from "../src/app.ts";
import type { Deps } from "../src/env.ts";
import { deleteAccount } from "../src/account.ts";
import { appleClientSecret, exchangeAuthorizationCode } from "../src/appleRevoke.ts";
import { signJwt } from "../src/jwt.ts";
import { grant, newUser, testEnv } from "./helpers.ts";

const env = { ...testEnv };
const deps: Deps = { now: () => Date.now(), sendEmail: async () => {}, fetch };

async function call(path: string, o: { method?: string; user?: string; body?: unknown } = {}) {
  const headers: Record<string, string> = {};
  if (o.user) headers.authorization = `Bearer ${await signJwt({ sub: o.user, exp: Math.floor(Date.now() / 1000) + 600 }, env.JWT_SECRET)}`;
  return handleRequest(new Request(`https://api.test${path}`, { method: o.method ?? "POST", headers, body: o.body === undefined ? undefined : JSON.stringify(o.body) }), env, deps);
}
const count = async (sql: string, ...args: unknown[]) => (await testEnv.DB.prepare(sql).bind(...args).first<{ n: number }>())!.n;

describe("DELETE /v1/account (App Store 5.1.1(v))", () => {
  it("needs a sign-in", async () => {
    expect((await call("/v1/account", { method: "DELETE" })).status).toBe(401);
  });

  it("erases the account and everything stored under it", async () => {
    const u = await newUser();
    await grant(u, "pro_yearly", { expires: Date.now() + 100 * 86_400_000 });
    await testEnv.DB.prepare("INSERT INTO refresh_tokens (token_hash, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)").bind(`h-${u}`, u, Date.now() + 1e9, Date.now()).run();
    await testEnv.DB.prepare("INSERT INTO rate_events (user_id, at) VALUES (?, ?)").bind(u, Date.now()).run();
    await testEnv.DB.prepare("INSERT INTO email_codes (email, code_hash, expires_at, window_start) VALUES (?, 'x', ?, ?)").bind(`${u}@test`, Date.now() + 1e6, Date.now()).run();

    const res = await call("/v1/account", { method: "DELETE", user: u });
    expect(res.status).toBe(200);
    for (const table of ["users", "refresh_tokens", "profiles", "entitlements", "usage_periods", "usage_events"]) {
      expect(await count(`SELECT COUNT(*) AS n FROM ${table} WHERE ${table === "users" ? "id" : "user_id"} = ?`, u), table).toBe(0);
    }
    expect(await count("SELECT COUNT(*) AS n FROM rate_events WHERE user_id = ?", u)).toBe(0);
    expect(await count("SELECT COUNT(*) AS n FROM email_codes WHERE email = ?", `${u}@test`)).toBe(0);
    // the deleted account's token no longer opens anything
    expect((await call("/v1/me", { method: "GET", user: u })).status).toBe(401);
  });

  it("is idempotent and leaves other accounts alone", async () => {
    const a = await newUser(), b = await newUser();
    expect((await call("/v1/account", { method: "DELETE", user: a })).status).toBe(200);
    expect((await call("/v1/account", { method: "DELETE", user: a })).status).toBeLessThan(500);
    expect(await count("SELECT COUNT(*) AS n FROM users WHERE id = ?", b)).toBe(1);
  });

  it("does not hand out the Free credits again on the same Mac", async () => {
    const hash = "a".repeat(64);
    const first = await newUser(false);
    expect((await call("/v1/trial/start", { user: first, body: { install_id_hash: hash } })).status).toBe(200);
    await call("/v1/account", { method: "DELETE", user: first });
    const second = await newUser(false);
    const again = await call("/v1/trial/start", { user: second, body: { install_id_hash: hash } });
    expect(again.status).toBe(409);
  });
});

describe("Sign in with Apple token revocation", () => {
  async function appleEnv() {
    const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
    const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
    const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----`;
    return { pair, env: { ...testEnv, APPLE_TEAM_ID: "TEAM123456", APPLE_KEY_ID: "KEY1234567", APPLE_PRIVATE_KEY: pem } };
  }
  const requests: { url: string; form: URLSearchParams }[] = [];
  const fakeFetch = (status = 200, body: unknown = {}) => (async (input: RequestInfo | URL, init?: RequestInit) => {
    requests.push({ url: String(input), form: new URLSearchParams(String(init?.body)) });
    return new Response(JSON.stringify(body), { status });
  }) as typeof fetch;

  it("signs a client secret Apple can verify", async () => {
    const { pair, env: e } = await appleEnv();
    const jwt = await appleClientSecret(e, Date.now());
    const [head, claims, sig] = jwt.split(".");
    const dec = (s: string) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
    expect(JSON.parse(new TextDecoder().decode(dec(head)))).toEqual({ alg: "ES256", kid: "KEY1234567" });
    expect(JSON.parse(new TextDecoder().decode(dec(claims)))).toMatchObject({ iss: "TEAM123456", aud: "https://appleid.apple.com", sub: "app.permylast" });
    expect(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pair.publicKey, dec(sig), new TextEncoder().encode(`${head}.${claims}`))).toBe(true);
  });

  it("trades an authorization code for a refresh token, and returns null if Apple refuses", async () => {
    const { env: e } = await appleEnv();
    requests.length = 0;
    expect(await exchangeAuthorizationCode(e, { ...deps, fetch: fakeFetch(200, { refresh_token: "r-1" }) }, "code-1")).toBe("r-1");
    expect(requests[0].url).toBe("https://appleid.apple.com/auth/token");
    expect(requests[0].form.get("code")).toBe("code-1");
    expect(requests[0].form.get("grant_type")).toBe("authorization_code");
    expect(await exchangeAuthorizationCode(e, { ...deps, fetch: fakeFetch(400, { error: "invalid_grant" }) }, "bad")).toBeNull();
  });

  it("revokes the stored token when the account is deleted, and still deletes if Apple fails", async () => {
    const { env: e } = await appleEnv();
    for (const status of [200, 500]) {
      const u = await newUser();
      await testEnv.DB.prepare("UPDATE users SET apple_refresh_token = ? WHERE id = ?").bind(`r-${status}`, u).run();
      requests.length = 0;
      await deleteAccount(e, { ...deps, fetch: fakeFetch(status) }, u);
      expect(requests).toHaveLength(1);
      expect(requests[0].url).toBe("https://appleid.apple.com/auth/revoke");
      expect(requests[0].form.get("token")).toBe(`r-${status}`);
      expect(requests[0].form.get("token_type_hint")).toBe("refresh_token");
      expect(await count("SELECT COUNT(*) AS n FROM users WHERE id = ?", u)).toBe(0);
    }
  });

  it("does nothing with Apple when the key is not configured", async () => {
    const u = await newUser();
    await testEnv.DB.prepare("UPDATE users SET apple_refresh_token = 'r' WHERE id = ?").bind(u).run();
    requests.length = 0;
    await deleteAccount(testEnv, { ...deps, fetch: fakeFetch() }, u);
    expect(requests).toHaveLength(0);
    expect(await count("SELECT COUNT(*) AS n FROM users WHERE id = ?", u)).toBe(0);
  });
});
