import { describe, expect, it } from "vitest";
import bundled from "../../Packages/PerMyLastCore/Sources/PerMyLastCore/Resources/Templates.json";
import { handleRequest } from "../src/app.ts";
import type { Deps } from "../src/env.ts";
import { signJwt } from "../src/jwt.ts";
import { DAY, grant, newUser, testEnv } from "./helpers.ts";

const NOW = Date.now();
const deps: Deps = { now: () => NOW, fetch, sendEmail: async () => {} };

async function call(path: string, o: { method?: string; user?: string | null; token?: string } = {}) {
  const headers: Record<string, string> = {};
  const token = o.token ?? (o.user ? await signJwt({ sub: o.user, exp: Math.floor(NOW / 1000) + 600 }, testEnv.JWT_SECRET) : null);
  if (token) headers.authorization = `Bearer ${token}`;
  return handleRequest(new Request(`https://api.test${path}`, { method: o.method ?? "GET", headers }), testEnv, deps);
}

describe("GET /v1/me", () => {
  it("returns the plan for a signed-in user", async () => {
    const u = await newUser();
        const res = await call("/v1/me", { user: u });
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(await res.json()).toMatchObject({ plan: "free", runs_used: 0, runs_allowance: 21, owns_lifetime: false, next_upgrade_tier: null });
  });

  it("an account that has not claimed its Mac has no plan yet", async () => {
    expect(await (await call("/v1/me", { user: await newUser(false) })).json()).toMatchObject({ plan: "none", runs_used: null, period_end: null });
  });

  it("is 401 without a valid token", async () => {
    for (const o of [{}, { token: "garbage" }, { token: await signJwt({ sub: "u", exp: 1 }, testEnv.JWT_SECRET) }, { token: await signJwt({ sub: "u", exp: 9999999999 }, "wrong-secret") }]) {
      const res = await call("/v1/me", o);
      expect(res.status).toBe(401);
      expect((await res.json<{ error: { code: string } }>()).error.code).toBe("unauthenticated");
    }
  });

  it("never exposes another user's data", async () => {
    const a = await newUser(), b = await newUser();
    await grant(a, "lifetime");
    expect((await (await call("/v1/me", { user: b })).json<{ owns_lifetime: boolean }>()).owns_lifetime).toBe(false);
  });
});

describe("GET /v1/templates", () => {
  it("serves the seeded templates, identical to the copy bundled in the app", async () => {
    const body = await (await call("/v1/templates", { user: await newUser() })).json<{ version: number; templates: { id: string }[] }>();
    expect(body.version).toBe(1);
    expect([...body.templates].sort((x, y) => x.id.localeCompare(y.id))).toEqual([...bundled.templates].sort((x, y) => x.id.localeCompare(y.id)));
  });

  it("is empty once the caller has the newest version", async () => {
    const u = await newUser();
    expect(await (await call("/v1/templates?since_version=1", { user: u })).json()).toEqual({ version: 1, templates: [] });
  });

  it("needs sign-in", async () => {
    expect((await call("/v1/templates")).status).toBe(401);
  });
});

describe("routing", () => {
  it("405 for a wrong method, 404 for an unknown path", async () => {
    expect((await call("/v1/me", { method: "POST", user: await newUser() })).status).toBe(405);
    expect((await call("/v1/nope")).status).toBe(404);
  });

  it("fails closed when the secret is missing", async () => {
    const res = await handleRequest(new Request("https://api.test/v1/me"), { ...testEnv, JWT_SECRET: "" }, deps);
    expect(res.status).toBe(500);
  });
});
