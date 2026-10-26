import { config } from "../config.ts";
import { loadPlanInputs } from "./metering.ts";
import { monthlyPeriod, nextUpgradeTier, resolvePlan, type Plan } from "./plans.ts";

export interface Me {
  plan: Plan;
  runs_used: number | null;
  runs_allowance: number | null;
  /** End of the current monthly period (Free and Pro): when credits renew. */
  period_end: string | null;
  owns_lifetime: boolean;
  updates_until: string | null;
  /** Power user only: which `lifetime_upgrade_N` product the next upgrade is (price halves each step). */
  next_upgrade_tier: number | null;
  /** Address on the account; for Sign in with Apple it may be a private relay address, or null if the person withheld it. */
  email: string | null;
  /** What to call the person (Sign in with Apple's full name), or null when we were never given one. */
  name: string | null;
  /** How this account signs in: Apple wins over Google, and an account with neither uses an emailed code. */
  provider: "apple" | "google" | "email";
}

const iso = (ms: number | null | undefined) => (ms == null ? null : new Date(ms).toISOString());

/** Body of GET /v1/me. */
export async function getMe(db: D1Database, userId: string, now = Date.now()): Promise<Me> {
  const { rows, freeEligible, freeAnchor, freeUsage } = await loadPlanInputs(db, userId, now);
  const { plan, entitlement } = resolvePlan(rows, freeEligible, now);

  const lifetimes = rows.filter((r) => r.plan === "lifetime" && r.status === "active");
  const updates = lifetimes.map((r) => r.updates_until).filter((v): v is number => v !== null);
  const upgrades = lifetimes.length ? Math.max(...lifetimes.map((r) => r.upgrade_count ?? 0)) : 0;

  const user = await db
    .prepare("SELECT email, name, apple_sub, google_sub FROM users WHERE id = ?")
    .bind(userId)
    .first<{ email: string | null; name: string | null; apple_sub: string | null; google_sub: string | null }>();

  let used: number | null = null;
  let allowance: number | null = null;
  let periodEnd: number | null = null;

  if ((plan === "pro_monthly" || plan === "pro_yearly") && entitlement) {
    const period = monthlyPeriod(entitlement.starts_at, now);
    const row = await db
      .prepare("SELECT used, allowance FROM usage_periods WHERE user_id = ? AND kind = 'pro' AND period_start = ?")
      .bind(userId, period.start)
      .first<{ used: number; allowance: number }>();
    used = row?.used ?? 0;
    allowance = row?.allowance ?? config.PRO_MONTHLY_RUNS;
    periodEnd = period.end;
  } else if (plan === "free") {
    used = freeUsage?.used ?? 0;
    allowance = freeUsage?.allowance ?? config.FREE_MONTHLY_CREDITS;
    periodEnd = monthlyPeriod(freeAnchor, now).end;
  }

  return {
    plan,
    runs_used: used,
    runs_allowance: allowance,
    period_end: iso(periodEnd),
    owns_lifetime: lifetimes.length > 0,
    updates_until: iso(updates.length ? Math.max(...updates) : null),
    next_upgrade_tier: lifetimes.length ? nextUpgradeTier(upgrades, config.UPGRADE_TIERS) : null,
    email: user?.email ?? null,
    name: user?.name ?? null,
    provider: user?.apple_sub ? "apple" : user?.google_sub ? "google" : "email",
  };
}
