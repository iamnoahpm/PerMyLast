// Plan resolution and period maths. Pure functions: no database, no clock (PRD section 2).

export type Plan = "none" | "free" | "lifetime" | "pro_monthly" | "pro_yearly";

export interface EntitlementRow {
  id: string;
  plan: "lifetime" | "pro_monthly" | "pro_yearly";
  status: "active" | "expired" | "refunded";
  starts_at: number;
  expires_at: number | null;
  updates_until: number | null;
  upgrade_count?: number;
}

export interface UsageCounts {
  used: number;
  allowance: number;
}

export interface Resolved {
  plan: Plan;
  entitlement: EntitlementRow | null;
}

const isPro = (p: string) => p === "pro_monthly" || p === "pro_yearly";

/**
 * First match wins: active Pro, then Power user (lifetime), then Free if this Mac has claimed it, else none.
 * Free never expires; running out of credits is decided by the metering write, not here.
 */
export function resolvePlan(rows: EntitlementRow[], freeEligible: boolean, now: number): Resolved {
  const pro = rows
    .filter((r) => isPro(r.plan) && r.status === "active" && r.starts_at <= now && (r.expires_at === null || r.expires_at > now))
    .sort((a, b) => (b.expires_at ?? Infinity) - (a.expires_at ?? Infinity))[0];
  if (pro) return { plan: pro.plan, entitlement: pro };

  const lifetime = rows.filter((r) => r.plan === "lifetime" && r.status === "active").sort((a, b) => b.starts_at - a.starts_at)[0];
  if (lifetime) return { plan: "lifetime", entitlement: lifetime };

  return freeEligible ? { plan: "free", entitlement: null } : { plan: "none", entitlement: null };
}

export type BlockReason = "no_entitlement";

/**
 * The tier of the upgrade a Power user buys next. Upgrade n costs 50% of the previous price, so the ladder is
 * `lifetime_upgrade_1` ... `_UPGRADE_TIERS`; past the last tier the last one is offered again.
 */
export function nextUpgradeTier(upgradeCount: number, tiers: number): number {
  return Math.min(upgradeCount + 1, tiers);
}

/** `start` plus `n` calendar months in UTC; a day that does not exist in the target month clamps to its last day. */
export function addMonths(start: number, n: number): number {
  const d = new Date(start);
  const day = d.getUTCDate();
  const first = Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + n, 1, d.getUTCHours(), d.getUTCMinutes(), d.getUTCSeconds(), d.getUTCMilliseconds());
  const target = new Date(first);
  const daysInMonth = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)).getUTCDate();
  target.setUTCDate(Math.min(day, daysInMonth));
  return target.getTime();
}

/**
 * The monthly period containing `now`, counted from the subscription's anchor date (yearly plans reset
 * monthly too). Always computed from the anchor, never iteratively, so month-end clamping cannot drift.
 */
export function monthlyPeriod(anchor: number, now: number): { start: number; end: number } {
  const a = new Date(anchor);
  const b = new Date(now);
  let n = Math.max(0, (b.getUTCFullYear() - a.getUTCFullYear()) * 12 + (b.getUTCMonth() - a.getUTCMonth()));
  while (addMonths(anchor, n + 1) <= now) n++;
  while (n > 0 && addMonths(anchor, n) > now) n--;
  return { start: addMonths(anchor, n), end: addMonths(anchor, n + 1) };
}
