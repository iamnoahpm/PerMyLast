// Onboarding funnel events. Anonymous and allowlisted: only the names below are stored, props are small flat
// values, and an install can only ever log so many (a cap, not a rate limit, because the funnel is a few events per install).
import { config } from "../config.ts";

/** The funnel, in order, then what happens after. Keep in step with OnboardingEvent in the app. */
export const EVENT_NAMES = new Set([
  "onboarding_started",
  "onboarding_step_viewed",
  "onboarding_sample_run",
  "onboarding_copy_clicked",
  "onboarding_accessibility_requested",
  "onboarding_shortcut_tested",
  "onboarding_access_trial_code_sent",
  "onboarding_access_trial_started",
  "onboarding_access_own_key_saved",
  "onboarding_skipped",
  "onboarding_completed",
  "first_real_run",
]);

type Props = Record<string, string | number | boolean>;
export type EventsResult = { ok: true; accepted: number } | { ok: false; reason: "bad_request" | "too_many" };

function cleanProps(value: unknown): Props | null | undefined {
  if (value === undefined) return null;
  if (!value || typeof value !== "object" || Array.isArray(value)) return undefined;
  const out: Props = {};
  const entries = Object.entries(value as Record<string, unknown>);
  if (entries.length > 4) return undefined;
  for (const [k, v] of entries) {
    if (!/^[a-z_]{1,24}$/.test(k)) return undefined;
    if (typeof v === "string" && v.length <= 40) out[k] = v;
    else if (typeof v === "number" && Number.isFinite(v)) out[k] = v;
    else if (typeof v === "boolean") out[k] = v;
    else return undefined;
  }
  return out;
}

export async function recordEvents(db: D1Database, body: Record<string, unknown> | null, now: number): Promise<EventsResult> {
  const install = body?.install_id_hash;
  const list = body?.events;
  if (typeof install !== "string" || !/^[0-9a-f]{64}$/.test(install)) return { ok: false, reason: "bad_request" };
  if (!Array.isArray(list) || list.length === 0 || list.length > config.EVENTS_PER_REQUEST) return { ok: false, reason: "bad_request" };
  const version = typeof body?.app_version === "string" && body.app_version.length <= 20 ? body.app_version : null;

  const rows: { name: string; at: number; props: string | null }[] = [];
  for (const item of list) {
    const e = item as { name?: unknown; at?: unknown; props?: unknown };
    if (typeof e?.name !== "string" || !EVENT_NAMES.has(e.name)) return { ok: false, reason: "bad_request" };
    const props = cleanProps(e.props);
    if (props === undefined) return { ok: false, reason: "bad_request" };
    // The device clock can be wrong; keep its time only when it is plausible, otherwise stamp the server's.
    const at = typeof e.at === "number" && Number.isFinite(e.at) && Math.abs(now - e.at) < 7 * 86_400_000 ? Math.round(e.at) : now;
    rows.push({ name: e.name, at, props: props ? JSON.stringify(props) : null });
  }

  const have = await db.prepare("SELECT COUNT(*) AS n FROM onboarding_events WHERE install_id = ?").bind(install).first<{ n: number }>();
  if ((have?.n ?? 0) + rows.length > config.EVENTS_PER_INSTALL) return { ok: false, reason: "too_many" };

  await db.batch(rows.map((r) =>
    db.prepare("INSERT INTO onboarding_events (install_id, name, at, app_version, props) VALUES (?, ?, ?, ?, ?)").bind(install, r.name, r.at, version, r.props)));
  return { ok: true, accepted: rows.length };
}
