import { describe, expect, it } from "vitest";
import { config } from "../config.ts";
import { handleRequest } from "../src/app.ts";
import type { Deps } from "../src/env.ts";
import { testEnv } from "./helpers.ts";

const now = Date.now();
const deps: Deps = { now: () => now, sendEmail: async () => {}, fetch: (async () => new Response("no")) as typeof fetch };
const hash = (c: string) => c.repeat(64);

async function post(body: unknown) {
  return handleRequest(new Request("https://api.test/v1/events", { method: "POST", body: JSON.stringify(body) }), testEnv, deps);
}
const count = async (install: string) =>
  (await testEnv.DB.prepare("SELECT COUNT(*) AS n FROM onboarding_events WHERE install_id = ?").bind(install).first<{ n: number }>())!.n;

describe("POST /v1/events", () => {
  it("stores known events without a sign-in", async () => {
    const res = await post({ install_id_hash: hash("a"), app_version: "1.2.0", events: [
      { name: "onboarding_started", at: now },
      { name: "onboarding_step_viewed", at: now, props: { step: "welcome", index: 1 } },
    ] });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, accepted: 2 });
    expect(await count(hash("a"))).toBe(2);
    const row = await testEnv.DB.prepare("SELECT props, app_version FROM onboarding_events WHERE install_id = ? AND name = 'onboarding_step_viewed'").bind(hash("a")).first<{ props: string; app_version: string }>();
    expect(JSON.parse(row!.props)).toEqual({ step: "welcome", index: 1 });
    expect(row!.app_version).toBe("1.2.0");
  });

  it("rejects unknown names, bad ids, long props and big batches, storing nothing", async () => {
    const id = hash("b");
    for (const body of [
      { install_id_hash: id, events: [{ name: "onboarding_started" }, { name: "typed_text" }] },
      { install_id_hash: "not-a-hash", events: [{ name: "onboarding_started" }] },
      { install_id_hash: id, events: [{ name: "onboarding_started", props: { note: "x".repeat(41) } }] },
      { install_id_hash: id, events: [{ name: "onboarding_started", props: { a: 1, b: 1, c: 1, d: 1, e: 1 } }] },
      { install_id_hash: id, events: [{ name: "onboarding_started", props: { email: { nested: true } } }] },
      { install_id_hash: id, events: [] },
      { install_id_hash: id, events: Array.from({ length: config.EVENTS_PER_REQUEST + 1 }, () => ({ name: "onboarding_started" })) },
    ]) {
      expect((await post(body)).status).toBe(400);
    }
    expect(await count(id)).toBe(0);
  });

  it("replaces an implausible device clock with the server's time", async () => {
    await post({ install_id_hash: hash("c"), events: [{ name: "onboarding_started", at: 5 }] });
    const row = await testEnv.DB.prepare("SELECT at FROM onboarding_events WHERE install_id = ?").bind(hash("c")).first<{ at: number }>();
    expect(row!.at).toBe(now);
  });

  it("caps what one install can log", async () => {
    const id = hash("d");
    const batch = Array.from({ length: config.EVENTS_PER_REQUEST }, () => ({ name: "onboarding_step_viewed" }));
    for (let i = 0; i < config.EVENTS_PER_INSTALL / config.EVENTS_PER_REQUEST; i++) expect((await post({ install_id_hash: id, events: batch })).status).toBe(200);
    expect((await post({ install_id_hash: id, events: [{ name: "onboarding_started" }] })).status).toBe(429);
    expect(await count(id)).toBe(config.EVENTS_PER_INSTALL);
  });
});
