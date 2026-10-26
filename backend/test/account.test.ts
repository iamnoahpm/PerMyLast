import { describe, expect, it } from "vitest";
import { handleRequest } from "../src/app.ts";
import type { Deps } from "../src/env.ts";
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
