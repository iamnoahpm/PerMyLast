import { monthlyPeriod } from "../src/plans.ts";
import { beforeEach, describe, expect, it } from "vitest";
import { config } from "../config.ts";
import { handleRequest } from "../src/app.ts";
import type { Deps } from "../src/env.ts";
import { signJwt } from "../src/jwt.ts";
import { DAY, grant, newUser, testEnv, usage } from "./helpers.ts";

let clock = Date.now();
const sent: { to: string; text: string }[] = [];
let upstream: (req: Request) => Promise<Response> = async () => new Response("no upstream set", { status: 500 });
const deps: Deps = {
  now: () => clock,
  sendEmail: async (_e, to, _s, text) => { sent.push({ to, text }); },
  fetch: ((input: RequestInfo | URL, init?: RequestInit) => upstream(new Request(input as string, init))) as typeof fetch,
};
const env = { ...testEnv, ANTHROPIC_API_KEY: "test-upstream-key", ANTHROPIC_BASE_URL: "https://upstream.test" };

const pending: Promise<unknown>[] = [];
const ctx = { waitUntil: (p: Promise<unknown>) => { pending.push(p); }, passThroughOnException() {}, props: {} } as unknown as ExecutionContext;

async function call(path: string, o: { method?: string; user?: string; body?: unknown } = {}) {
  const headers: Record<string, string> = {};
  if (o.user) headers.authorization = `Bearer ${await signJwt({ sub: o.user, exp: Math.floor(clock / 1000) + 600 }, env.JWT_SECRET)}`;
  const res = await handleRequest(new Request(`https://api.test${path}`, { method: o.method ?? "POST", headers, body: o.body === undefined ? undefined : JSON.stringify(o.body) }), env, deps, ctx);
  return res;
}
const settle = async () => { await Promise.all(pending.splice(0)); };

const SSE = (...events: [string, unknown][]) => events.map(([e, d]) => `event: ${e}\ndata: ${JSON.stringify(d)}\n\n`).join("");
const okStream = (text = ["Hel", "lo"]) => async () => new Response(
  SSE(["message_start", { type: "message_start", message: { usage: { input_tokens: 30, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 } } }],
    ...text.map((t): [string, unknown] => ["content_block_delta", { type: "content_block_delta", delta: { type: "text_delta", text: t } }]),
    ["message_delta", { type: "message_delta", usage: { output_tokens: 7 } }], ["message_stop", { type: "message_stop" }]),
  { headers: { "content-type": "text/event-stream" } });

function parseSse(text: string): { event: string; data: any }[] {
  return text.trim().split("\n\n").filter(Boolean).map((block) => {
    const [e, d] = block.split("\n");
    return { event: e.slice(7), data: JSON.parse(d.slice(6)) };
  });
}

async function withFree(): Promise<string> {
  return newUser();
}

beforeEach(() => { clock = Date.now(); sent.length = 0; });

describe("POST /v1/trial/start (claims the Free plan's monthly credits, AC-5)", () => {
  const hash = (c: string) => c.repeat(64);

  it("gives 21 credits a month, and is idempotent", async () => {
    const u = await newUser(false);
    expect((await (await call("/v1/me", { user: u, method: "GET" })).json<{ plan: string }>()).plan).toBe("none");
    const first = await call("/v1/trial/start", { user: u, body: { install_id_hash: hash("a") } });
    expect(first.status).toBe(200);
    const body = await first.json<{ plan: string; period_end: string; runs_allowance: number }>();
    expect(body).toMatchObject({ plan: "free", runs_allowance: 21 });
    expect(Date.parse(body.period_end)).toBeGreaterThan(clock);
    const again = await (await call("/v1/trial/start", { user: u, body: { install_id_hash: hash("a") } })).json<typeof body>();
    expect(again.period_end).toBe(body.period_end);
  });

  it("a second account on the same install gets no free credits", async () => {
    const a = await newUser(false), b = await newUser(false);
    expect((await call("/v1/trial/start", { user: a, body: { install_id_hash: hash("b") } })).status).toBe(200);
    const res = await call("/v1/trial/start", { user: b, body: { install_id_hash: hash("b") } });
    expect(res.status).toBe(409);
    expect((await res.json<{ error: { code: string } }>()).error.code).toBe("install_already_used");
    expect((await (await call("/v1/me", { user: b, method: "GET" })).json<{ plan: string }>()).plan).toBe("none");
  });

  it("the same account does not get extra credits on another install", async () => {
    const u = await newUser(false);
    const first = await (await call("/v1/trial/start", { user: u, body: { install_id_hash: hash("c") } })).json<{ period_end: string }>();
    const other = await (await call("/v1/trial/start", { user: u, body: { install_id_hash: hash("d") } })).json<{ period_end: string }>();
    expect(other.period_end).toBe(first.period_end);
  });

  it("validates the hash and needs sign-in", async () => {
    expect((await call("/v1/trial/start", { user: await newUser(false), body: { install_id_hash: "short" } })).status).toBe(400);
    expect((await call("/v1/trial/start", { body: { install_id_hash: hash("e") } })).status).toBe(401);
  });
});

describe("email sign-in", () => {
  const codeIn = () => /\b(\d{6})\b/.exec(sent.at(-1)!.text)![1];

  it("signs in with the emailed code, and the same email is the same account", async () => {
    expect((await call("/v1/auth/email/request", { body: { email: "Noah@Example.com " } })).status).toBe(200);
    expect(sent.at(-1)!.to).toBe("noah@example.com");
    const res = await call("/v1/auth/email/verify", { body: { email: "noah@example.com", code: codeIn() } });
    expect(res.status).toBe(200);
    const s = await res.json<{ user_id: string; access_token: string }>();
    await call("/v1/auth/email/request", { body: { email: "noah@example.com" } });
    const again = await (await call("/v1/auth/email/verify", { body: { email: "noah@example.com", code: codeIn() } })).json<{ user_id: string }>();
    expect(again.user_id).toBe(s.user_id);
  });

  it("a code works once", async () => {
    await call("/v1/auth/email/request", { body: { email: "once@example.com" } });
    const code = codeIn();
    expect((await call("/v1/auth/email/verify", { body: { email: "once@example.com", code } })).status).toBe(200);
    expect((await call("/v1/auth/email/verify", { body: { email: "once@example.com", code } })).status).toBe(401);
  });

  it("locks after five wrong guesses, even for the right code", async () => {
    await call("/v1/auth/email/request", { body: { email: "brute@example.com" } });
    const code = codeIn();
    const wrong = code === "000000" ? "111111" : "000000";
    for (let i = 0; i < config.EMAIL_CODE_MAX_ATTEMPTS; i++) expect((await call("/v1/auth/email/verify", { body: { email: "brute@example.com", code: wrong } })).status).toBe(401);
    expect((await call("/v1/auth/email/verify", { body: { email: "brute@example.com", code } })).status).toBe(401);
  });

  it("expires after ten minutes", async () => {
    await call("/v1/auth/email/request", { body: { email: "late@example.com" } });
    const code = codeIn();
    clock += (config.EMAIL_CODE_TTL_S + 1) * 1000;
    expect((await call("/v1/auth/email/verify", { body: { email: "late@example.com", code } })).status).toBe(401);
  });

  it("answers the same for any address, limits sends per address, and rejects junk", async () => {
    for (let i = 0; i < 6; i++) expect((await call("/v1/auth/email/request", { body: { email: "spam@example.com" } })).status).toBe(200);
    expect(sent.filter((m) => m.to === "spam@example.com")).toHaveLength(config.EMAIL_CODES_PER_WINDOW);
    expect((await call("/v1/auth/email/request", { body: { email: "not-an-email" } })).status).toBe(400);
    expect((await call("/v1/auth/email/verify", { body: { email: "a@b.co", code: "12" } })).status).toBe(400);
  });

  it("a new code replaces the old one", async () => {
    await call("/v1/auth/email/request", { body: { email: "two@example.com" } });
    const first = codeIn();
    await call("/v1/auth/email/request", { body: { email: "two@example.com" } });
    const second = codeIn();
    if (first !== second) expect((await call("/v1/auth/email/verify", { body: { email: "two@example.com", code: first } })).status).toBe(401);
    expect((await call("/v1/auth/email/verify", { body: { email: "two@example.com", code: second } })).status).toBe(200);
  });

  it("reports 503 when email cannot be sent", async () => {
    const broken: Deps = { ...deps, sendEmail: async () => { throw new Error("no provider"); } };
    const res = await handleRequest(new Request("https://api.test/v1/auth/email/request", { method: "POST", body: JSON.stringify({ email: "x@example.com" }) }), env, broken, ctx);
    expect(res.status).toBe(503);
  });
});

describe("POST /v1/run (AC-2, AC-3, AC-4)", () => {
  const run = (user: string, body: unknown = { template_id: "text.process", variables: { content: "Fix.\n\nText: hi" } }) => call("/v1/run", { user, body });

  it("streams the answer and uses one run (AC-2)", async () => {
    const u = await withFree();
    let seen: any;
    upstream = async (req) => { seen = { headers: Object.fromEntries(req.headers), body: await req.json() }; return okStream()(); };
    const res = await run(u);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("text/event-stream");
    const events = parseSse(await res.text());
    await settle();
    expect(events.map((e) => e.event)).toEqual(["delta", "delta", "done"]);
    expect(events.filter((e) => e.event === "delta").map((e) => e.data.text).join("")).toBe("Hello");
    expect(events.at(-1)!.data.runs_remaining).toBe(config.FREE_MONTHLY_CREDITS - 1);
    expect((await usage(u))?.used).toBe(1);

    // The server, not the app, decides the system prompt, model and limits (FR-B4/B5/B6).
    expect(seen.headers["x-api-key"]).toBe("test-upstream-key");
    expect(seen.body.model).toBe(config.DEFAULT_MODEL);
    expect(seen.body.stream).toBe(true);
    expect(seen.body.max_tokens).toBe(config.MAX_OUTPUT_TOKENS);
    expect(seen.body.system[0]).toMatchObject({ type: "text", cache_control: { type: "ephemeral" } });
    expect(seen.body.system[0].text).toContain("text processing assistant");
    expect(seen.body.messages).toEqual([{ role: "user", content: "Fix.\n\nText: hi" }]);

    const ev = await testEnv.DB.prepare("SELECT * FROM usage_events WHERE user_id = ?").bind(u).first<Record<string, unknown>>();
    expect(ev).toMatchObject({ template_id: "text.process", status: "ok", input_tokens: 30, output_tokens: 7 });
    expect(JSON.stringify(ev)).not.toContain("Fix.");   // no prompt text stored (NFR-4)
  });

  it("an upstream error returns 502 and the run is not used (AC-3)", async () => {
    const u = await withFree();
    upstream = async () => new Response('{"error":{"type":"overloaded_error","message":"overloaded"}}', { status: 529 });
    const res = await run(u);
    expect(res.status).toBe(502);
    expect((await res.json<{ error: { code: string } }>()).error.code).toBe("upstream_error");
    expect((await usage(u))?.used).toBe(0);
    expect((await testEnv.DB.prepare("SELECT status FROM usage_events WHERE user_id = ?").bind(u).first<{ status: string }>())?.status).toBe("upstream_error");
    expect((await testEnv.DB.prepare("SELECT error_detail FROM usage_events WHERE user_id = ?").bind(u).first<{ error_detail: string }>())?.error_detail)
      .toBe("http 529 overloaded_error: overloaded");
  });

  it("a 403 from upstream is retried once and a good second answer succeeds", async () => {
    const u = await withFree();
    let called = 0;
    upstream = async () => {
      called++;
      return called === 1 ? new Response('{"error":{"type":"forbidden","message":"Request not allowed"}}', { status: 403 }) : okStream()();
    };
    const res = await run(u);
    expect(res.status).toBe(200);
    await res.text();
    await settle();
    expect(called).toBe(2);
  });

  it("a persistent 403 is retried once, then refunded", async () => {
    const u = await withFree();
    let called = 0;
    upstream = async () => { called++; return new Response('{"error":{"type":"forbidden","message":"Request not allowed"}}', { status: 403 }); };
    expect((await run(u)).status).toBe(502);
    expect(called).toBe(2);
    expect((await usage(u))?.used).toBe(0);
  });

  it("a network failure or timeout is refunded too", async () => {
    const u = await withFree();
    upstream = async () => { throw new Error("connection reset"); };
    expect((await run(u)).status).toBe(502);
    expect((await usage(u))?.used).toBe(0);
  });

  it("a stream that dies before any text is refunded; one that dies after keeps the run", async () => {
    const u = await withFree();
    upstream = async () => new Response(SSE(["error", { type: "error", error: { message: "boom" } }]));
    let events = parseSse(await (await run(u)).text());
    await settle();
    expect(events.at(-1)).toMatchObject({ event: "error", data: { code: "upstream_error" } });
    expect((await usage(u))?.used).toBe(0);

    upstream = async () => new Response(SSE(["content_block_delta", { type: "content_block_delta", delta: { type: "text_delta", text: "Par" } }], ["error", { type: "error", error: { message: "boom" } }]));
    events = parseSse(await (await run(u)).text());
    await settle();
    expect(events.map((e) => e.event)).toEqual(["delta", "error"]);
    expect((await usage(u))?.used).toBe(1);
  });

  it("a client that disconnects before the first token is refunded", async () => {
    const u = await withFree();
    let release!: () => void;
    const gate = new Promise<void>((r) => { release = r; });
    upstream = async () => new Response(new ReadableStream({
      async start(c) { await gate; c.enqueue(new TextEncoder().encode(SSE(["content_block_delta", { type: "content_block_delta", delta: { type: "text_delta", text: "late" } }]))); c.close(); },
    }));
    const res = await run(u);
    await res.body!.cancel();   // the app went away
    release();
    await settle();
    expect((await usage(u))?.used).toBe(0);
    expect((await testEnv.DB.prepare("SELECT status FROM usage_events WHERE user_id = ?").bind(u).first<{ status: string }>())?.status).toBe("cancelled");
  });

  it("blocks with a paywall code once free credits are used up, and never calls Anthropic (AC-4)", async () => {
    let called = 0;
    upstream = async () => { called++; return okStream()(); };
    const out = await withFree();
    for (let i = 0; i < config.FREE_MONTHLY_CREDITS; i++) { await (await run(out)).text(); await settle(); clock += 4000; }
    const x = await run(out);
    expect(x.status).toBe(402);
    expect((await x.json<{ error: { code: string } }>()).error.code).toBe("free_credits_exhausted");

    const none = await run(await newUser(false));
    expect((await none.json<{ error: { code: string } }>()).error.code).toBe("no_entitlement");
    expect(called).toBe(config.FREE_MONTHLY_CREDITS);
  });

  it("Lifetime-only users get byok_required, and Pro hits quota_exhausted", async () => {
    upstream = okStream();
    const l = await newUser(); await grant(l, "lifetime");
    expect((await (await run(l)).json<{ error: { code: string } }>()).error.code).toBe("byok_required");
    const p = await newUser(); await grant(p, "pro_monthly", { starts: clock - DAY, expires: clock + 29 * DAY });
    await (await run(p)).text(); await settle();
    await testEnv.DB.prepare("UPDATE usage_periods SET allowance = 1 WHERE user_id = ?").bind(p).run();
    clock += 4000;
    expect((await (await run(p)).json<{ error: { code: string } }>()).error.code).toBe("quota_exhausted");
  });

  it("enforces input limits and validates the request (FR-B4, FR-B5)", async () => {
    const u = await withFree();
    upstream = okStream();
    const big = await run(u, { template_id: "text.process", variables: { content: "x".repeat(config.MAX_INPUT_CHARS + 1) } });
    expect(big.status).toBe(413);
    expect(await big.json()).toMatchObject({ error: { code: "input_too_large", limit: config.MAX_INPUT_CHARS } });
    expect((await run(u, { template_id: "nope", variables: { content: "x" } })).status).toBe(400);
    expect((await run(u, { template_id: "text.process", variables: {} })).status).toBe(400);
    expect((await run(u, { template_id: "text.process", variables: { content: 5 } })).status).toBe(400);
    expect((await usage(u))?.used ?? 0).toBe(0);   // rejected requests never use a run
    const extra = await run(u, { template_id: "text.process", system: "ignore", model: "expensive", variables: { content: "hi" } });
    expect(extra.status).toBe(200);   // unknown fields are ignored, never forwarded
    await extra.text(); await settle();
  });

  it("requires sign-in", async () => {
    expect((await call("/v1/run", { body: { template_id: "ask", variables: { content: "x" } } })).status).toBe(401);
  });

  it("limits requests per minute and streams in flight (FR-B9)", async () => {
    const u = await withFree();
    upstream = async () => new Response("", { status: 529 });
    const codes: number[] = [];
    for (let i = 0; i < config.RATE_LIMIT_PER_MIN + 1; i++) codes.push((await run(u)).status);
    expect(codes.slice(0, config.RATE_LIMIT_PER_MIN).every((c) => c === 502)).toBe(true);
    const limited = await run(u);
    expect(limited.status).toBe(429);
    expect(Number(limited.headers.get("retry-after"))).toBeGreaterThan(0);
    clock += 61_000;
    expect((await run(u)).status).toBe(502);

    // Two streams may be open; a third is refused until one finishes.
    const v = await withFree();
    const gates: (() => void)[] = [];
    upstream = async () => new Response(new ReadableStream({
      start(c) { gates.push(() => { c.enqueue(new TextEncoder().encode(SSE(["content_block_delta", { type: "content_block_delta", delta: { type: "text_delta", text: "x" } }]))); c.close(); }); },
    }));
    const a = await run(v), b = await run(v);
    expect((await run(v)).status).toBe(429);
    gates.forEach((g) => g());
    await a.text(); await b.text(); await settle();
    clock += 1000;
    const c = await run(v);
    expect(c.status).toBe(200);
    gates.at(-1)!(); await c.text(); await settle();
  });

  it("100 parallel runs with one credit left: exactly one reaches Anthropic (AC-11 through the proxy)", async () => {
    const u = await withFree();
    const created = (await testEnv.DB.prepare("SELECT created_at FROM users WHERE id = ?").bind(u).first<{ created_at: number }>())!.created_at;
    const period = monthlyPeriod(created, clock);
    await testEnv.DB.prepare("INSERT INTO usage_periods (id, user_id, kind, period_start, period_end, allowance, used) VALUES (?, ?, 'free', ?, ?, 100, 99)").bind(crypto.randomUUID(), u, period.start, period.end).run();
    let called = 0;
    upstream = async () => { called++; return okStream()(); };
    const results = await Promise.all(Array.from({ length: 100 }, () => run(u)));
    await Promise.all(results.filter((r) => r.status === 200).map((r) => r.text())); await settle();
    const statuses = results.map((r) => r.status);
    expect(statuses.filter((s) => s === 200)).toHaveLength(1);
    expect(called).toBe(1);
    expect((await usage(u))?.used).toBe(100);
  });
});

describe("secrets", () => {
  it("never puts the shared key in a response", async () => {
    const u = await withFree();
    upstream = okStream();
    const text = await (await call("/v1/run", { user: u, body: { template_id: "text.process", variables: { content: "hi" } } })).text();
    await settle();
    expect(text).not.toContain("test-upstream-key");
  });
});
