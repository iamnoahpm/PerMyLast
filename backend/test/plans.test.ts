import { describe, expect, it } from "vitest";
import { addMonths, blockReason, monthlyPeriod, resolvePlan, type EntitlementRow } from "../src/plans.ts";

const NOW = Date.UTC(2026, 9, 22, 12);
const DAY = 86_400_000;
const row = (plan: EntitlementRow["plan"], o: Partial<EntitlementRow> = {}): EntitlementRow => ({
  id: plan, plan, status: "active", starts_at: NOW - DAY, expires_at: null, updates_until: null, ...o,
});

describe("resolvePlan", () => {
  it("is none without entitlements", () => expect(resolvePlan([], null, NOW).plan).toBe("none"));

  it("orders Pro > Lifetime > trial", () => {
    const trial = row("trial", { expires_at: NOW + 20 * DAY });
    expect(resolvePlan([trial], null, NOW).plan).toBe("trial");
    expect(resolvePlan([trial, row("lifetime")], null, NOW).plan).toBe("lifetime");
    expect(resolvePlan([trial, row("lifetime"), row("pro_yearly", { expires_at: NOW + 300 * DAY })], null, NOW).plan).toBe("pro_yearly");
  });

  it("a lapsed Pro falls back to Lifetime", () => {
    const pro = row("pro_monthly", { expires_at: NOW - 1 });
    expect(resolvePlan([pro, row("lifetime")], null, NOW).plan).toBe("lifetime");
  });

  it("ignores refunded and expired rows", () => {
    expect(resolvePlan([row("pro_monthly", { status: "refunded", expires_at: NOW + DAY })], null, NOW).plan).toBe("none");
    expect(resolvePlan([row("lifetime", { status: "expired" })], null, NOW).plan).toBe("none");
  });

  it("a trial ends at day 21 or when credits run out", () => {
    const trial = row("trial", { expires_at: NOW + DAY });
    expect(resolvePlan([trial], { used: 49, allowance: 50 }, NOW).plan).toBe("trial");
    expect(resolvePlan([trial], { used: 50, allowance: 50 }, NOW).plan).toBe("none");
    expect(resolvePlan([row("trial", { expires_at: NOW - 1 })], null, NOW).plan).toBe("none");
  });
});

describe("blockReason", () => {
  it("tells the cases apart", () => {
    expect(blockReason([], null, NOW)).toBe("no_entitlement");
    expect(blockReason([row("trial", { expires_at: NOW - 1 })], null, NOW)).toBe("trial_expired");
    expect(blockReason([row("trial", { expires_at: NOW + DAY })], { used: 50, allowance: 50 }, NOW)).toBe("trial_credits_exhausted");
    expect(blockReason([row("trial", { status: "expired", expires_at: NOW + DAY })], null, NOW)).toBe("trial_expired");
  });
});

describe("monthly periods", () => {
  const t = (iso: string) => Date.parse(iso);
  it("clamps month-end anchors without drifting", () => {
    const anchor = t("2026-01-31T10:00:00Z");
    expect(addMonths(anchor, 1)).toBe(t("2026-02-28T10:00:00Z"));
    expect(addMonths(anchor, 2)).toBe(t("2026-03-31T10:00:00Z"));
    expect(monthlyPeriod(anchor, t("2026-02-28T09:00:00Z")).start).toBe(anchor);
    expect(monthlyPeriod(anchor, t("2026-02-28T12:00:00Z"))).toEqual({ start: t("2026-02-28T10:00:00Z"), end: t("2026-03-31T10:00:00Z") });
    expect(monthlyPeriod(anchor, t("2026-03-31T12:00:00Z")).start).toBe(t("2026-03-31T10:00:00Z"));
  });

  it("starts the first period at the anchor", () => {
    const a = t("2026-01-15T00:00:00Z");
    expect(monthlyPeriod(a, a)).toEqual({ start: a, end: t("2026-02-15T00:00:00Z") });
  });

  it("finds the right month 40 days in", () => {
    const a = NOW - 40 * DAY;
    const p = monthlyPeriod(a, NOW);
    expect(p.start).toBeLessThanOrEqual(NOW);
    expect(p.end).toBeGreaterThan(NOW);
    expect(NOW - p.start).toBeLessThan(31 * DAY);
  });
});
