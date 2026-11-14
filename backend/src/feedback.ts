// Run ratings. Anonymous (keyed by a hashed install id, no sign-in), allowlisted, and size-capped. A rating alone stores only
// settings. The prompt, input and output are stored only when the app sends them with `shared: true`, which it does only after
// the person agreed on a screen that showed them exactly that text.
import { config } from "../config.ts";

export type FeedbackResult = { ok: true } | { ok: false; reason: "bad_request" | "too_many" };

const RATINGS = new Set(["bad", "fine", "good"]);
const VIA = new Set(["proxy", "own_key"]);

/** A short setting-like value: optional, single line, bounded. */
function short(value: unknown, max: number): string | null | undefined {
  if (value === undefined || value === null) return null;
  return typeof value === "string" && value.length <= max ? value : undefined;
}

function long(value: unknown, max: number): string | undefined {
  return typeof value === "string" && value.length <= max ? value : undefined;
}

export async function recordFeedback(db: D1Database, body: Record<string, unknown> | null, now: number): Promise<FeedbackResult> {
  const bad = { ok: false, reason: "bad_request" } as const;
  const install = body?.install_id_hash;
  const id = body?.feedback_id;
  const rating = body?.rating;
  if (typeof install !== "string" || !/^[0-9a-f]{64}$/.test(install)) return bad;
  if (typeof id !== "string" || !/^[0-9A-Fa-f-]{36}$/.test(id)) return bad;
  if (typeof rating !== "string" || !RATINGS.has(rating)) return bad;

  const version = short(body?.app_version, 20), os = short(body?.os_version, 40), lang = short(body?.app_language, 12);
  const model = short(body?.model, 60), effort = short(body?.effort, 12), mode = short(body?.mode, 40), preset = short(body?.preset, 60);
  const via = body?.via === undefined ? null : typeof body.via === "string" && VIA.has(body.via) ? body.via : undefined;
  const images = body?.image_count === undefined ? null : Number.isInteger(body.image_count) && (body.image_count as number) >= 0 && (body.image_count as number) <= 20 ? (body.image_count as number) : undefined;
  if ([version, os, lang, model, effort, mode, preset, via, images].includes(undefined)) return bad;

  let prompt: string | null = null, input: string | null = null, output: string | null = null;
  const shared = body?.shared === true;
  if (shared) {
    const p = long(body?.prompt, config.FEEDBACK_MAX_PROMPT_CHARS);
    const i = long(body?.input, config.MAX_INPUT_CHARS);
    const o = long(body?.output, config.FEEDBACK_MAX_OUTPUT_CHARS);
    if (p === undefined || i === undefined || o === undefined) return bad;
    prompt = p; input = i; output = o;
  }

  const existing = await db.prepare("SELECT install_id, shared FROM run_feedback WHERE id = ?").bind(id).first<{ install_id: string; shared: number }>();
  if (existing) {
    if (existing.install_id !== install) return bad;
    if (existing.shared) return { ok: true }; // already stored; a repeat changes nothing
    await db.prepare("UPDATE run_feedback SET rating = ?, shared = ?, shared_at = ?, prompt = ?, input_text = ?, output_text = ? WHERE id = ?")
      .bind(rating, shared ? 1 : 0, shared ? now : null, prompt, input, output, id).run();
    return { ok: true };
  }

  const have = await db.prepare("SELECT COUNT(*) AS n FROM run_feedback WHERE install_id = ?").bind(install).first<{ n: number }>();
  if ((have?.n ?? 0) >= config.FEEDBACK_PER_INSTALL) return { ok: false, reason: "too_many" };
  await db.prepare(
    `INSERT INTO run_feedback (id, install_id, created_at, shared_at, rating, app_version, os_version, app_language, model, effort, mode, preset, via, image_count, shared, prompt, input_text, output_text)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  ).bind(id, install, now, shared ? now : null, rating, version, os, lang, model, effort, mode, preset, via, images, shared ? 1 : 0, prompt, input, output).run();
  return { ok: true };
}
