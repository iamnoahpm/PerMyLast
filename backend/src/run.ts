// POST /v1/run: the Claude proxy. The shared key lives only here (NFR-1). The client names a template and
// supplies variables; the system prompt, model and token limit come from the server (FR-B4, FR-B5).
import { config } from "../config.ts";
import type { Deps, Env } from "./env.ts";
import { releaseStreamSlot, takeRateSlot, takeStreamSlot } from "./limits.ts";
import { getMe } from "./me.ts";
import { commitRun, consumeRun, refundRun, RunError, type RunErrorCode } from "./metering.ts";

export interface Template {
  id: string;
  system: string;
  user_template: string;
  variables: string[];
  model: string | null;
  max_tokens: number;
}

type Fail = (status: number, code: string, message: string, extra?: Record<string, unknown>) => Response;

/** Fills `{{variable}}` in one pass, like the app does, so a value containing `{{…}}` is never expanded. */
export function renderTemplate(t: Template, values: Record<string, string>): string {
  let out = "";
  let rest = t.user_template;
  for (;;) {
    const open = rest.indexOf("{{");
    const close = open < 0 ? -1 : rest.indexOf("}}", open + 2);
    if (open < 0 || close < 0) return out + rest;
    out += rest.slice(0, open);
    const name = rest.slice(open + 2, close);
    out += Object.hasOwn(values, name) ? values[name] : rest.slice(open, close + 2);
    rest = rest.slice(close + 2);
  }
}

const RUN_ERRORS: Record<RunErrorCode, { status: number; message: string }> = {
  byok_required: { status: 402, message: "Your plan uses your own Anthropic API key." },
  quota_exhausted: { status: 402, message: "You've used this month's runs." },
  trial_credits_exhausted: { status: 402, message: "You've used all your free trial runs." },
  trial_expired: { status: 402, message: "Your free trial has ended." },
  no_entitlement: { status: 402, message: "Start your free trial or choose a plan to continue." },
};

interface UpstreamUsage { input: number; output: number; cacheRead: number; cacheWrite: number }

const sse = (event: string, data: unknown) => new TextEncoder().encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);

export async function handleRun(req: Request, env: Env, deps: Deps, ctx: ExecutionContext, userId: string, fail: Fail): Promise<Response> {
  const started = deps.now();

  const rate = await takeRateSlot(env.DB, userId, started);
  if (!rate.ok) {
    const res = fail(429, "rate_limited", "Too many requests. Try again shortly.", { retry_after: rate.retryAfter });
    res.headers.set("retry-after", String(rate.retryAfter));
    return res;
  }

  let body: { template_id?: unknown; variables?: unknown };
  try {
    const text = await req.text();
    if (text.length > config.MAX_INPUT_CHARS * 4 + 4096) return fail(413, "input_too_large", "That input is too large.", { limit: config.MAX_INPUT_CHARS });
    body = JSON.parse(text);
  } catch {
    return fail(400, "bad_request", "Invalid JSON.");
  }
  const vars = body.variables;
  if (typeof body.template_id !== "string" || !vars || typeof vars !== "object" || Array.isArray(vars)
      || !Object.values(vars).every((v) => typeof v === "string")) {
    return fail(400, "bad_request", "template_id and string variables are required.");
  }
  const variables = vars as Record<string, string>;

  const row = await env.DB.prepare("SELECT json FROM templates WHERE id = ? AND active = 1").bind(body.template_id).first<{ json: string }>();
  if (!row) return fail(400, "unknown_template", "Unknown template.");
  const template = JSON.parse(row.json) as Template;
  if (template.variables.some((name) => !Object.hasOwn(variables, name))) return fail(400, "bad_request", "A template variable is missing.");

  const inputChars = Object.values(variables).reduce((n, v) => n + v.length, 0);
  if (inputChars > config.MAX_INPUT_CHARS) return fail(413, "input_too_large", `Input is limited to ${config.MAX_INPUT_CHARS} characters.`, { limit: config.MAX_INPUT_CHARS });

  const slotOrNull = await takeStreamSlot(env.DB, userId, started);
  if (!slotOrNull) return fail(429, "rate_limited", "Too many requests in progress.", { retry_after: 5 });

  const slot: string = slotOrNull;
  let reservation: string;
  try {
    reservation = await consumeRun(env.DB, userId, started);
  } catch (error) {
    await releaseStreamSlot(env.DB, slot);
    if (error instanceof RunError) {
      const info = RUN_ERRORS[error.code];
      return fail(info.status, error.code, info.message);
    }
    throw error;
  }

  const model = template.model ?? config.DEFAULT_MODEL;
  const record = (status: string, usage?: UpstreamUsage) =>
    env.DB.prepare(
      `INSERT INTO usage_events (id, user_id, template_id, model, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, latency_ms, status, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(crypto.randomUUID(), userId, template.id, model, usage?.input ?? null, usage?.output ?? null, usage?.cacheRead ?? null,
      usage?.cacheWrite ?? null, deps.now() - started, status, deps.now()).run();
  const giveBack = async (status: string, usage?: UpstreamUsage) => {
    await refundRun(env.DB, reservation); // FR-B7
    await record(status, usage);
    await releaseStreamSlot(env.DB, slot);
  };

  // Everything before the first streamed byte can still fail cleanly with a normal HTTP error.
  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort("timeout"), config.UPSTREAM_TIMEOUT_S * 1000);
  let upstream: Response;
  try {
    if (!env.ANTHROPIC_API_KEY) throw new Error("ANTHROPIC_API_KEY is not set");
    upstream = await deps.fetch(`${env.ANTHROPIC_BASE_URL ?? "https://api.anthropic.com"}/v1/messages`, {
      method: "POST",
      signal: abort.signal,
      headers: { "x-api-key": env.ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({
        model,
        max_tokens: Math.min(template.max_tokens, config.MAX_OUTPUT_TOKENS),
        stream: true,
        system: [{ type: "text", text: template.system, cache_control: { type: "ephemeral" } }], // FR-B6
        messages: [{ role: "user", content: renderTemplate(template, variables) }],
      }),
    });
  } catch (error) {
    clearTimeout(timer);
    await giveBack(abort.signal.aborted ? "timeout" : "upstream_error");
    console.error("upstream failed", error instanceof Error ? error.message : error);
    return fail(502, "upstream_error", "The AI service is unavailable. Your run was not used.");
  }
  if (!upstream.ok || !upstream.body) {
    clearTimeout(timer);
    await giveBack("upstream_error");
    console.error("upstream status", upstream.status);
    return fail(502, "upstream_error", "The AI service is unavailable. Your run was not used.");
  }

  const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
  const writer = writable.getWriter();
  ctx.waitUntil(pump());
  return new Response(readable, {
    headers: { "content-type": "text/event-stream", "cache-control": "no-store", "x-accel-buffering": "no" },
  });

  async function pump(): Promise<void> {
    const usage: UpstreamUsage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
    let delivered = false;
    let clientGone = false;
    let status = "ok";
    // A write fails once the app has gone away; remember that so the run is not blamed on the AI service.
    const send = async (chunk: Uint8Array) => {
      try { await writer.write(chunk); } catch (error) { clientGone = true; throw error; }
    };
    try {
      const reader = upstream.body!.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        let newline: number;
        while ((newline = buffer.indexOf("\n")) >= 0) {
          const line = buffer.slice(0, newline).trimEnd();
          buffer = buffer.slice(newline + 1);
          if (!line.startsWith("data:")) continue;
          let event: Record<string, any>;
          try { event = JSON.parse(line.slice(5)); } catch { continue; }
          if (event.type === "message_start") {
            const u = event.message?.usage ?? {};
            usage.input = u.input_tokens ?? 0; usage.cacheRead = u.cache_read_input_tokens ?? 0; usage.cacheWrite = u.cache_creation_input_tokens ?? 0;
            usage.output = u.output_tokens ?? 0;
          } else if (event.type === "message_delta") {
            usage.output = event.usage?.output_tokens ?? usage.output;
          } else if (event.type === "content_block_delta" && event.delta?.type === "text_delta" && event.delta.text) {
            await send(sse("delta", { text: event.delta.text }));
            if (!delivered) { delivered = true; await commitRun(env.DB, reservation); }
          } else if (event.type === "error") {
            throw new Error("upstream error event");
          }
        }
      }
      if (!delivered) throw new Error("no text from upstream");
      const me = await getMe(env.DB, userId, deps.now());
      const remaining = me.runs_allowance != null && me.runs_used != null ? Math.max(0, me.runs_allowance - me.runs_used) : null;
      await send(sse("done", { runs_remaining: remaining }));
    } catch (error) {
      status = clientGone ? "cancelled" : abort.signal.aborted ? "timeout" : "upstream_error";
      if (!delivered) await refundRun(env.DB, reservation); // FR-B7: nothing reached the user
      if (!clientGone) {
        const message = delivered ? "The answer was cut short." : "The AI service stopped responding. Your run was not used.";
        try { await writer.write(sse("error", { code: "upstream_error", message })); } catch { /* client gone */ }
      }
    } finally {
      clearTimeout(timer);
      abort.abort();
      await record(status, usage).catch(() => {});
      await releaseStreamSlot(env.DB, slot).catch(() => {});
      await writer.close().catch(() => {});
    }
  }
}
