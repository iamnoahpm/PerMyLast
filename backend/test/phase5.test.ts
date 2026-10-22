import { describe, expect, it } from "vitest";
import { config } from "../config.ts";
import { handleRequest } from "../src/app.ts";
import type { Deps } from "../src/env.ts";
import { signJwt } from "../src/jwt.ts";
import { getMe } from "../src/me.ts";
import { consumeRun, refundRun, runWeight } from "../src/metering.ts";
import { DAY, grant, newUser, testEnv, usage } from "./helpers.ts";

const db = testEnv.DB;

describe("NFR-6: larger models cost more runs", () => {
  it("weights by model family", () => {
    expect(runWeight(config.DEFAULT_MODEL)).toBe(1);
    expect(runWeight("claude-haiku-4-5")).toBe(1);
    for (const m of ["claude-opus-5", "claude-sonnet-5", "claude-fable-5"]) expect(runWeight(m)).toBe(config.EXPENSIVE_MODEL_WEIGHT);
  });

  it("a heavy run uses its weight, a refund gives back exactly that much", async () => {
    const u = await newUser();
    await grant(u, "trial", { starts: Date.now(), expires: Date.now() + 21 * DAY });
    const light = await consumeRun(db, u, Date.now(), 1);
    const heavy = await consumeRun(db, u, Date.now(), 4);
    expect((await usage(u))?.used).toBe(5);
    await refundRun(db, heavy);
    await refundRun(db, heavy);
    expect((await usage(u))?.used).toBe(1);
    await refundRun(db, light);
    expect((await usage(u))?.used).toBe(0);
  });

  it("a heavy run needs enough runs left", async () => {
    const u = await newUser();
    await grant(u, "pro_monthly", { starts: Date.now() - DAY, expires: Date.now() + 29 * DAY });
    await consumeRun(db, u);
    await db.prepare("UPDATE usage_periods SET allowance = 5, used = 3 WHERE user_id = ?").bind(u).run();
    await expect(consumeRun(db, u, Date.now(), 4)).rejects.toMatchObject({ code: "quota_exhausted" });
    expect((await usage(u))?.used).toBe(3);
    await consumeRun(db, u, Date.now(), 2);
    expect((await usage(u))?.used).toBe(5);
  });

  it("100 parallel heavy runs with room for exactly three: three succeed", async () => {
    const u = await newUser();
    await grant(u, "pro_monthly", { starts: Date.now() - DAY, expires: Date.now() + 29 * DAY });
    await consumeRun(db, u);
    await db.prepare("UPDATE usage_periods SET allowance = 12, used = 0 WHERE user_id = ?").bind(u).run();
    const results = await Promise.all(Array.from({ length: 100 }, () => consumeRun(db, u, Date.now(), 4).then(() => "ok", () => "no")));
    expect(results.filter((r) => r === "ok")).toHaveLength(3);
    expect((await usage(u))?.used).toBe(12);
  });

  it("through the proxy: a template on a larger model is charged its weight, and a failed one is refunded in full", async () => {
    await db.prepare("UPDATE templates SET active = 0 WHERE id = 'ask'").run();
    await db.prepare("INSERT INTO templates (id, version, json, active) VALUES ('ask', 2, ?, 1)")
      .bind(JSON.stringify({ id: "ask", version: 2, system: "s", user_template: "{{content}}", variables: ["content"], model: "claude-sonnet-5", max_tokens: 99999 })).run();
    const u = await newUser();
    await grant(u, "trial", { starts: Date.now(), expires: Date.now() + 21 * DAY });

    let seen: any;
    const ok: Deps = { now: () => Date.now(), sendEmail: async () => {}, fetch: (async (_u: unknown, init: RequestInit) => {
      seen = JSON.parse(init.body as string);
      return new Response('event: content_block_delta\ndata: {"type":"content_block_delta","delta":{"type":"text_delta","text":"hi"}}\n\n');
    }) as unknown as typeof fetch };
    const pending: Promise<unknown>[] = [];
    const ctx = { waitUntil: (p: Promise<unknown>) => pending.push(p), passThroughOnException() {}, props: {} } as unknown as ExecutionContext;
    const token = await signJwt({ sub: u, exp: Math.floor(Date.now() / 1000) + 600 }, testEnv.JWT_SECRET);
    const call = (d: Deps) => handleRequest(new Request("https://api.test/v1/run", { method: "POST", headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ template_id: "ask", variables: { content: "x" } }) }),
      { ...testEnv, ANTHROPIC_API_KEY: "k" }, d, ctx);

    const res = await call(ok);
    const text = await res.text();
    await Promise.all(pending.splice(0));
    expect(text).toContain("event: done");
    expect(seen.model).toBe("claude-sonnet-5");
    expect(seen.max_tokens).toBe(config.MAX_OUTPUT_TOKENS);                       // a template can never exceed the cap (NFR-5)
    expect((await getMe(db, u)).runs_used).toBe(config.EXPENSIVE_MODEL_WEIGHT);

    const failing: Deps = { ...ok, fetch: (async () => new Response("", { status: 529 })) as unknown as typeof fetch };
    const bad = await call(failing);
    expect(bad.status).toBe(502);
    expect((await getMe(db, u)).runs_used).toBe(config.EXPENSIVE_MODEL_WEIGHT);   // refunded in full
  });
});

describe("NFR-4: no prompt or output text is stored", () => {
  it("no column of any table holds the text of a run", async () => {
    const marker = "ZZ-UNIQUE-PROMPT-MARKER-ZZ";
    const u = await newUser();
    await grant(u, "trial", { starts: Date.now(), expires: Date.now() + 21 * DAY });
    const deps: Deps = { now: () => Date.now(), sendEmail: async () => {}, fetch: (async () =>
      new Response(`event: content_block_delta\ndata: {"type":"content_block_delta","delta":{"type":"text_delta","text":"${marker}-OUT"}}\n\n`)) as unknown as typeof fetch };
    const pending: Promise<unknown>[] = [];
    const ctx = { waitUntil: (p: Promise<unknown>) => pending.push(p), passThroughOnException() {}, props: {} } as unknown as ExecutionContext;
    const token = await signJwt({ sub: u, exp: Math.floor(Date.now() / 1000) + 600 }, testEnv.JWT_SECRET);
    const res = await handleRequest(new Request("https://api.test/v1/run", { method: "POST", headers: { authorization: `Bearer ${token}` },
      body: JSON.stringify({ template_id: "text.process", variables: { content: `${marker}-IN` } }) }), { ...testEnv, ANTHROPIC_API_KEY: "k" }, deps, ctx);
    await res.text();
    await Promise.all(pending.splice(0));

    const { results: tables } = await db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' AND name <> 'd1_migrations'").all<{ name: string }>();
    for (const { name } of tables) {
      const { results } = await db.prepare(`SELECT * FROM ${name}`).all();
      expect(JSON.stringify(results), `table ${name}`).not.toContain(marker);
    }
  });
});
