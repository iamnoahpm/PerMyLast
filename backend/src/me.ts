import { config } from "../config.ts";
import { loadEntitlements, loadTrialUsage } from "./metering.ts";
import { monthlyPeriod, resolvePlan, type Plan } from "./plans.ts";

export interface Me {
  plan: Plan;
  trial_ends_at: string | null;
  runs_used: number | null;
  runs_allowance: number | null;
  period_end: string | null;
  owns_lifetime: boolean;
  updates_until: string | null;
}

const iso = (ms: number | null | undefined) => (ms == null ? null : new Date(ms).toISOString());

/** Body of GET /v1/me. */
export async function getMe(db: D1Database, userId: string, now = Date.now()): Promise<Me> {
  const rows = await loadEntitlements(db, userId);
  const trial = rows.find((r) => r.plan === "trial");
  const trialUsage = await loadTrialUsage(db, userId, rows);
  const { plan, entitlement } = resolvePlan(rows, trialUsage, now);

  const lifetimes = rows.filter((r) => r.plan === "lifetime" && r.status === "active");
  const updates = lifetimes.map((r) => r.updates_until).filter((v): v is number => v !== null);

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
  } else if (trial && (plan === "trial" || plan === "none")) {
    // Trial numbers while it runs, and after it ends so the app can say why.
    used = trialUsage?.used ?? 0;
    allowance = trialUsage?.allowance ?? config.TRIAL_CREDITS;
    periodEnd = trial.expires_at;
  }

  return {
    plan,
    trial_ends_at: iso(trial?.expires_at),
    runs_used: used,
    runs_allowance: allowance,
    period_end: iso(periodEnd),
    owns_lifetime: lifetimes.length > 0,
    updates_until: iso(updates.length ? Math.max(...updates) : null),
  };
}
