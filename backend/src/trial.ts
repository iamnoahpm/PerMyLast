import { config } from "../config.ts";
import { getMe } from "./me.ts";

const HASH_RE = /^[0-9a-f]{64}$/;

export type TrialResult =
  | { ok: true; plan: string; trial_ends_at: string | null; runs_allowance: number }
  | { ok: false; reason: "bad_request" | "trial_already_used" };

/**
 * POST /v1/trial/start. Idempotent: calling it again returns the same trial. One trial per account and per
 * install: a second account on the same Mac gets `trial_already_used` (AC-5).
 */
export async function startTrial(db: D1Database, userId: string, installIdHash: unknown, now: number): Promise<TrialResult> {
  if (typeof installIdHash !== "string" || !HASH_RE.test(installIdHash)) return { ok: false, reason: "bad_request" };

  const existing = await db.prepare("SELECT 1 FROM entitlements WHERE user_id = ? AND plan = 'trial'").bind(userId).first();
  if (!existing) {
    try {
      // The unique index on install_id_hash is what stops a second account on the same install.
      await db.prepare("UPDATE profiles SET install_id_hash = ? WHERE user_id = ? AND install_id_hash IS NULL").bind(installIdHash, userId).run();
    } catch {
      return { ok: false, reason: "trial_already_used" };
    }
    await db
      .prepare("INSERT OR IGNORE INTO entitlements (id, user_id, plan, status, starts_at, expires_at, source, updated_at) VALUES (?, ?, 'trial', 'active', ?, ?, 'manual', ?)")
      .bind(crypto.randomUUID(), userId, now, now + config.TRIAL_DAYS * 86_400_000, now).run();
  }

  const me = await getMe(db, userId, now);
  return { ok: true, plan: me.plan, trial_ends_at: me.trial_ends_at, runs_allowance: config.TRIAL_CREDITS };
}
