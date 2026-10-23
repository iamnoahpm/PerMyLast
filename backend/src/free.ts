import { config } from "../config.ts";
import { getMe } from "./me.ts";

const HASH_RE = /^[0-9a-f]{64}$/;

export type FreeResult =
  | { ok: true; plan: string; period_end: string | null; runs_allowance: number }
  | { ok: false; reason: "bad_request" | "install_already_used" };

/**
 * POST /v1/trial/start (route name kept for installed apps). Claims the Free plan's monthly credits for this Mac.
 * Idempotent. One Mac gives credits to one account: a second account on the same install gets `install_already_used`
 * (AC-5), which stops sign-up loops from multiplying the free credits.
 */
export async function startFree(db: D1Database, userId: string, installIdHash: unknown, now: number): Promise<FreeResult> {
  if (typeof installIdHash !== "string" || !HASH_RE.test(installIdHash)) return { ok: false, reason: "bad_request" };

  try {
    // The unique index on install_id_hash is what stops a second account on the same install.
    await db.prepare("UPDATE profiles SET install_id_hash = ? WHERE user_id = ? AND install_id_hash IS NULL").bind(installIdHash, userId).run();
  } catch {
    return { ok: false, reason: "install_already_used" };
  }

  const me = await getMe(db, userId, now);
  return { ok: true, plan: me.plan, period_end: me.period_end, runs_allowance: config.FREE_MONTHLY_CREDITS };
}
