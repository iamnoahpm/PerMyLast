import { describe, expect, it } from "vitest";
import { addMonths, monthlyPeriod, nextUpgradeTier, resolvePlan, type EntitlementRow } from "../src/plans.ts";

const NOW = Date.UTC(2026, 9, 22, 12);
const DAY = 86_400_000;
const row = (plan: EntitlementRow["plan"], o: Partial<EntitlementRow> = {}): EntitlementRow => ({
  id: plan, plan, status: "active", starts_at: NOW - DAY, expires_at: null, updates_until: null, ...o,
});

describe("resolvePlan", () => {
  it("is none without entitlements or a claimed Mac", () => expect(resolvePlan([], false, NOW).plan).toBe("none"));
  it("is free once the Mac is claimed", () => expect(resolvePlan([], true, NOW).plan).toBe("free"));

  it("orders Pro > Power user > Free", () => {
    expect(resolvePlan([row("lifetime")], true, NOW).plan).toBe("lifetime");
    expect(resolvePlan([row("lifetime"), row("pro_yearly", { expires_at: NOW + 300 * DAY })], true, NOW).plan).toBe("pro_yearly");
  });

  it("a lapsed Pro falls back to Power user, then Free", () => {
    const pro = row("pro_monthly", { expires_at: NOW - 1 });
    expect(resolvePlan([pro, row("lifetime")], true, NOW).plan).toBe("lifetime");
    expect(resolvePlan([pro], true, NOW).plan).toBe("free");
  });

  it("ignores refunded and expired rows", () => {
    expect(resolvePlan([row("pro_monthly", { status: "refunded", expires_at: NOW + DAY })], false, NOW).plan).toBe("none");
    expect(resolvePlan([row("lifetime", { status: "expired" })], true, NOW).plan).toBe("free");
  });
});

describe("nextUpgradeTier", () => {
  it("steps down the ladder one product per upgrade and stays on the last", () => {
    expect([0, 1, 2, 3, 4, 9].map((n) => nextUpgradeTier(n, 3))).toEqual([1, 2, 3, 3, 3, 3]);
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
