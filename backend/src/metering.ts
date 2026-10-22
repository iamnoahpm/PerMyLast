// Atomic run metering on D1 (PRD FR-B3). The limit check is part of the write itself
// (`... WHERE used < allowance`), never a read followed by a write, and each reserve/refund is one
// D1 batch, which runs as a single transaction.
import { config } from "../config.ts";
import { blockReason, monthlyPeriod, resolvePlan, type EntitlementRow, type UsageCounts } from "./plans.ts";

export type RunErrorCode =
  | "byok_required"
  | "quota_exhausted"
  | "trial_credits_exhausted"
  | "trial_expired"
  | "no_entitlement";

export class RunError extends Error {
  constructor(readonly code: RunErrorCode) {
    super(code);
  }
}

export async function loadEntitlements(db: D1Database, userId: string): Promise<EntitlementRow[]> {
  const { results } = await db
    .prepare("SELECT id, plan, status, starts_at, expires_at, updates_until FROM entitlements WHERE user_id = ?")
    .bind(userId)
    .all<EntitlementRow>();
  return results;
}

export async function loadTrialUsage(db: D1Database, userId: string, rows: EntitlementRow[]): Promise<UsageCounts | null> {
  const trial = rows.find((r) => r.plan === "trial");
  if (!trial) return null;
  return db
    .prepare("SELECT used, allowance FROM usage_periods WHERE user_id = ? AND kind = 'trial' AND period_start = ?")
    .bind(userId, trial.starts_at)
    .first<UsageCounts>();
}

/** Reserves one run and returns the reservation id. Throws RunError with the PRD's code when it cannot. */
export async function consumeRun(db: D1Database, userId: string, now = Date.now()): Promise<string> {
  const rows = await loadEntitlements(db, userId);
  const trialUsage = await loadTrialUsage(db, userId, rows);
  const { plan, entitlement } = resolvePlan(rows, trialUsage, now);

  if (plan === "lifetime") throw new RunError("byok_required");
  if (plan === "none" || !entitlement) throw new RunError(blockReason(rows, trialUsage, now));

  const isTrial = plan === "trial";
  const kind = isTrial ? "trial" : "pro";
  const period = isTrial
    ? { start: entitlement.starts_at, end: entitlement.expires_at!, allowance: config.TRIAL_CREDITS }
    : { ...monthlyPeriod(entitlement.starts_at, now), allowance: config.PRO_MONTHLY_RUNS };

  await db
    .prepare("INSERT OR IGNORE INTO usage_periods (id, user_id, kind, period_start, period_end, allowance, used) VALUES (?, ?, ?, ?, ?, ?, 0)")
    .bind(crypto.randomUUID(), userId, kind, period.start, period.end, period.allowance)
    .run();

  const reservationId = crypto.randomUUID();
  const where = "user_id = ? AND kind = ? AND period_start = ? AND used < allowance";
  const [reserve] = await db.batch([
    db
      .prepare(`INSERT INTO run_reservations (id, usage_period_id, status, created_at)
                SELECT ?, id, 'reserved', ? FROM usage_periods WHERE ${where}`)
      .bind(reservationId, now, userId, kind, period.start),
    db
      .prepare(`UPDATE usage_periods SET used = used + 1
                WHERE ${where} AND EXISTS (SELECT 1 FROM run_reservations WHERE id = ?)`)
      .bind(userId, kind, period.start, reservationId),
  ]);
  if (reserve.meta.changes !== 1) throw new RunError(isTrial ? "trial_credits_exhausted" : "quota_exhausted");
  return reservationId;
}

/** Gives the run back (failed, cancelled before the first token, or timed out). Idempotent. */
export async function refundRun(db: D1Database, reservationId: string): Promise<void> {
  await db.batch([
    db
      .prepare(`UPDATE usage_periods SET used = MAX(used - 1, 0)
                WHERE id = (SELECT usage_period_id FROM run_reservations WHERE id = ? AND status = 'reserved')`)
      .bind(reservationId),
    db.prepare("UPDATE run_reservations SET status = 'refunded' WHERE id = ? AND status = 'reserved'").bind(reservationId),
  ]);
}

/** Marks a delivered run so a late refund cannot take it back. Idempotent. */
export async function commitRun(db: D1Database, reservationId: string): Promise<void> {
  await db.prepare("UPDATE run_reservations SET status = 'committed' WHERE id = ? AND status = 'reserved'").bind(reservationId).run();
}
