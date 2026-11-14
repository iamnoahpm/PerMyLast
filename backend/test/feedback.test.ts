import { describe, expect, it } from "vitest";
import { config } from "../config.ts";
import { handleRequest } from "../src/app.ts";
import type { Deps } from "../src/env.ts";
import { testEnv } from "./helpers.ts";

const now = Date.now();
const deps: Deps = { now: () => now, sendEmail: async () => {}, fetch: (async () => new Response("no")) as typeof fetch };
const hash = (c: string) => c.repeat(64);
const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const base = { app_version: "1.2.0", os_version: "macOS 15.1", model: "claude-sonnet-5", effort: "medium", mode: "Reply", preset: "Polite", via: "proxy", image_count: 0 };

async function post(body: unknown) {
  return handleRequest(new Request("https://api.test/v1/feedback", { method: "POST", body: JSON.stringify(body) }), testEnv, deps);
}
const row = (id: string) => testEnv.DB.prepare("SELECT * FROM run_feedback WHERE id = ?").bind(id).first<Record<string, unknown>>();

describe("POST /v1/feedback", () => {
  it("stores a rating with settings only, no text", async () => {
    const res = await post({ install_id_hash: hash("a"), feedback_id: uuid(1), rating: "good", ...base, prompt: "secret", input: "secret", output: "secret" });
    expect(res.status).toBe(200);
    const r = await row(uuid(1));
    expect(r).toMatchObject({ rating: "good", model: "claude-sonnet-5", app_version: "1.2.0", shared: 0, prompt: null, input_text: null, output_text: null });
  });

  it("adds the text to the same row once the person agrees, and not twice", async () => {
    await post({ install_id_hash: hash("b"), feedback_id: uuid(2), rating: "bad", ...base });
    await post({ install_id_hash: hash("b"), feedback_id: uuid(2), rating: "bad", ...base, shared: true, prompt: "P", input: "I", output: "O" });
    expect(await row(uuid(2))).toMatchObject({ shared: 1, prompt: "P", input_text: "I", output_text: "O", shared_at: now });
    await post({ install_id_hash: hash("b"), feedback_id: uuid(2), rating: "good", ...base, shared: true, prompt: "X", input: "X", output: "X" });
    expect(await row(uuid(2))).toMatchObject({ rating: "bad", prompt: "P" });
  });

  it("will not let another install change a row", async () => {
    await post({ install_id_hash: hash("c"), feedback_id: uuid(3), rating: "fine", ...base });
    const res = await post({ install_id_hash: hash("d"), feedback_id: uuid(3), rating: "good", ...base, shared: true, prompt: "P", input: "I", output: "O" });
    expect(res.status).toBe(400);
    expect(await row(uuid(3))).toMatchObject({ rating: "fine", shared: 0 });
  });

  it("rejects bad ratings, ids, settings and oversized shared text", async () => {
    const ok = { install_id_hash: hash("e"), feedback_id: uuid(4), rating: "good", ...base };
    for (const body of [
      { ...ok, rating: "great" },
      { ...ok, install_id_hash: "nope" },
      { ...ok, feedback_id: "not-a-uuid" },
      { ...ok, via: "elsewhere" },
      { ...ok, model: "x".repeat(61) },
      { ...ok, shared: true, prompt: "P", input: "I".repeat(config.MAX_INPUT_CHARS + 1), output: "O" },
      { ...ok, shared: true, prompt: "P" },
    ]) {
      expect((await post(body)).status).toBe(400);
    }
    expect(await row(uuid(4))).toBeNull();
  });

  it("caps how much one install can send", async () => {
    const id = hash("f");
    await testEnv.DB.batch(Array.from({ length: config.FEEDBACK_PER_INSTALL }, (_, n) =>
      testEnv.DB.prepare("INSERT INTO run_feedback (id, install_id, created_at, rating) VALUES (?, ?, ?, 'good')").bind(uuid(1000 + n), id, now)));
    expect((await post({ install_id_hash: id, feedback_id: uuid(5), rating: "good", ...base })).status).toBe(429);
  });
});
