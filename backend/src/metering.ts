// Atomic run metering on D1 (PRD FR-B3). The limit check is part of the write itself
// (`... WHERE used < allowance`), never a read followed by a write, and each reserve/refund is one
// D1 batch, which runs as a single transaction.
import { config } from "../config.ts";
import { monthlyPeriod, resolvePlan, type EntitlementRow, type UsageCounts } from "./plans.ts";

export type RunErrorCode = "byok_required" | "quota_exhausted" | "free_credits_exhausted" | "no_entitlement";

export class RunError extends Error {
  constructor(readonly code: RunErrorCode) {
    super(code);
  }
}

export async function loadEntitlements(db: D1Database, userId: string): Promise<EntitlementRow[]> {
  const { results } = await db
    .prepare("SELECT id, plan, status, starts_at, expires_at, updates_until, upgrade_count FROM entitlements WHERE user_id = ?")
    .bind(userId)
    .all<EntitlementRow>();
  return results;
}

export interface PlanInputs {
  rows: EntitlementRow[];
  /** Free is available once this Mac has been claimed (see free.ts). */
  freeEligible: boolean;
  /** Start of the account's monthly Free period, anchored on sign-up. */
  freeAnchor: number;
  /** Usage of the current Free period, if a run has been made in it. */
  freeUsage: UsageCounts | null;
}

/** Entitlements, Free eligibility and Free usage in one D1 round trip (every request pays for round trips, NFR-10). */
export async function loadPlanInputs(db: D1Database, userId: string, now: number): Promise<PlanInputs> {
  const [ents, profile, usage] = await db.batch([
    db.prepare("SELECT id, plan, status, starts_at, expires_at, updates_until, upgrade_count FROM entitlements WHERE user_id = ?").bind(userId),
    db.prepare("SELECT p.install_id_hash IS NOT NULL AS claimed, u.created_at FROM users u LEFT JOIN profiles p ON p.user_id = u.id WHERE u.id = ?").bind(userId),
    db.prepare("SELECT used, allowance FROM usage_periods WHERE user_id = ? AND kind = 'free' AND period_start <= ? AND period_end > ?").bind(userId, now, now),
  ]);
  const who = (profile.results as unknown as { claimed: number; created_at: number }[])[0];
  return {
    rows: ents.results as unknown as EntitlementRow[],
    freeEligible: who?.claimed === 1,
    freeAnchor: who?.created_at ?? now,
    freeUsage: (usage.results as unknown as UsageCounts[])[0] ?? null,
  };
}

/** Runs a model costs (NFR-6): 1 for the default class, `EXPENSIVE_MODEL_WEIGHT` for larger models. */
export function runWeight(model: string): number {
  return config.EXPENSIVE_MODEL_PREFIXES.some((p) => model.startsWith(p)) ? config.EXPENSIVE_MODEL_WEIGHT : 1;
}

/** Reserves `weight` runs (default 1) and returns the reservation id. Throws RunError with the PRD's code when it cannot. */
export async function consumeRun(db: D1Database, userId: string, now = Date.now(), weight = 1): Promise<string> {
  const inputs = await loadPlanInputs(db, userId, now);
  const { plan, entitlement } = resolvePlan(inputs.rows, inputs.freeEligible, now);

  if (plan === "lifetime") throw new RunError("byok_required");
  if (plan === "none") throw new RunError("no_entitlement");

  const isFree = plan === "free";
  const kind = isFree ? "free" : "pro";
  const period = isFree
    ? { ...monthlyPeriod(inputs.freeAnchor, now), allowance: config.FREE_MONTHLY_CREDITS }
    : { ...monthlyPeriod(entitlement!.starts_at, now), allowance: config.PRO_MONTHLY_RUNS };

  const reservationId = crypto.randomUUID();
  const where = "user_id = ? AND kind = ? AND period_start = ? AND used + ? <= allowance";
  const [, reserve] = await db.batch([
    db
      .prepare("INSERT OR IGNORE INTO usage_periods (id, user_id, kind, period_start, period_end, allowance, used) VALUES (?, ?, ?, ?, ?, ?, 0)")
      .bind(crypto.randomUUID(), userId, kind, period.start, period.end, period.allowance),
    db
      .prepare(`INSERT INTO run_reservations (id, usage_period_id, status, created_at, weight)
                SELECT ?, id, 'reserved', ?, ? FROM usage_periods WHERE ${where}`)
      .bind(reservationId, now, weight, userId, kind, period.start, weight),
    db
      .prepare(`UPDATE usage_periods SET used = used + ?
                WHERE ${where} AND EXISTS (SELECT 1 FROM run_reservations WHERE id = ?)`)
      .bind(weight, userId, kind, period.start, weight, reservationId),
  ]);
  if (reserve.meta.changes !== 1) throw new RunError(isFree ? "free_credits_exhausted" : "quota_exhausted");
  return reservationId;
}

/** Gives the run back (failed, cancelled before the first token, or timed out). Idempotent. */
export async function refundRun(db: D1Database, reservationId: string): Promise<void> {
  await db.batch([
    db
      .prepare(`UPDATE usage_periods SET used = MAX(used - (SELECT weight FROM run_reservations WHERE id = ? AND status = 'reserved'), 0)
                WHERE id = (SELECT usage_period_id FROM run_reservations WHERE id = ? AND status = 'reserved')`)
      .bind(reservationId, reservationId),
    db.prepare("UPDATE run_reservations SET status = 'refunded' WHERE id = ? AND status = 'reserved'").bind(reservationId),
  ]);
}

/** Marks a delivered run so a late refund cannot take it back. Idempotent. */
export async function commitRun(db: D1Database, reservationId: string): Promise<void> {
  await db.prepare("UPDATE run_reservations SET status = 'committed' WHERE id = ? AND status = 'reserved'").bind(reservationId).run();
}
