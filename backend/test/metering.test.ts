import { describe, expect, it } from "vitest";
import { config } from "../config.ts";
import { getMe } from "../src/me.ts";
import { commitRun, consumeRun, refundRun, RunError } from "../src/metering.ts";
import { DAY, grant, newUser, testEnv, usage } from "./helpers.ts";

const db = testEnv.DB;
const code = async (p: Promise<unknown>) => p.then(() => "ok", (e) => (e instanceof RunError ? e.code : String(e)));

describe("free", () => {
  it("meters runs and refunds them", async () => {
    const u = await newUser();
    const res = await consumeRun(db, u);
    const me = await getMe(db, u);
    expect([me.plan, me.runs_used, me.runs_allowance]).toEqual(["free", 1, config.FREE_MONTHLY_CREDITS]);
    expect(me.period_end).not.toBeNull();
    await refundRun(db, res);
    expect((await getMe(db, u)).runs_used).toBe(0);
  });

  it("stops at the credit limit, still reports usage, and stays on the free plan", async () => {
    const u = await newUser();
    for (let i = 0; i < config.FREE_MONTHLY_CREDITS; i++) await consumeRun(db, u);
    expect(await code(consumeRun(db, u))).toBe("free_credits_exhausted");
    const me = await getMe(db, u);
    expect([me.plan, me.runs_used]).toEqual(["free", config.FREE_MONTHLY_CREDITS]);
  });

  it("renews the credits every month", async () => {
    const u = await newUser();
    for (let i = 0; i < config.FREE_MONTHLY_CREDITS; i++) await consumeRun(db, u);
    expect(await code(consumeRun(db, u))).toBe("free_credits_exhausted");
    const nextMonth = Date.now() + 32 * DAY;
    expect(await code(consumeRun(db, u, nextMonth))).toBe("ok");
    expect((await getMe(db, u, nextMonth)).runs_used).toBe(1);
  });

  it("an account that has not claimed its Mac gets no_entitlement", async () => {
    expect(await code(consumeRun(db, await newUser(false)))).toBe("no_entitlement");
  });
});

describe("Pro and Lifetime", () => {
  it("Lifetime-only users must bring their own key", async () => {
    const u = await newUser();
    await grant(u, "lifetime", { updates: Date.now() + 365 * DAY });
    expect(await code(consumeRun(db, u))).toBe("byok_required");
    const me = await getMe(db, u);
    expect([me.plan, me.owns_lifetime, me.runs_used]).toEqual(["lifetime", true, null]);
    expect(me.updates_until).not.toBeNull();
  });

  it("Pro uses the shared key with a monthly allowance, and beats Lifetime", async () => {
    const u = await newUser();
    await grant(u, "lifetime");
    await grant(u, "pro_yearly", { starts: Date.now() - 40 * DAY, expires: Date.now() + 325 * DAY });
    await consumeRun(db, u);
    const me = await getMe(db, u);
    expect([me.plan, me.runs_used, me.runs_allowance, me.owns_lifetime]).toEqual(["pro_yearly", 1, config.PRO_MONTHLY_RUNS, true]);
    expect(Date.parse(me.period_end!)).toBeGreaterThan(Date.now());
  });

  it("raises quota_exhausted at the allowance", async () => {
    const u = await newUser();
    await grant(u, "pro_monthly", { starts: Date.now() - DAY, expires: Date.now() + 29 * DAY });
    await consumeRun(db, u);
    await db.prepare("UPDATE usage_periods SET allowance = 3 WHERE user_id = ?").bind(u).run();
    await consumeRun(db, u);
    await consumeRun(db, u);
    expect(await code(consumeRun(db, u))).toBe("quota_exhausted");
    expect((await usage(u))?.used).toBe(3);
  });

  it("a lapsed Pro falls back to Lifetime", async () => {
    const u = await newUser();
    await grant(u, "lifetime");
    await grant(u, "pro_monthly", { starts: Date.now() - 40 * DAY, expires: Date.now() - DAY });
    expect((await getMe(db, u)).plan).toBe("lifetime");
  });
});

describe("reservations", () => {
  it("refunding twice, or after commit, changes nothing", async () => {
    const u = await newUser();
    const a = await consumeRun(db, u);
    const b = await consumeRun(db, u);
    await refundRun(db, a);
    await refundRun(db, a);
    expect((await usage(u))?.used).toBe(1);
    await commitRun(db, b);
    await refundRun(db, b);
    expect((await usage(u))?.used).toBe(1);
    await refundRun(db, crypto.randomUUID());
  });
});

describe("AC-11: concurrency", () => {
  it("100 parallel runs at allowance - 1: exactly one succeeds", async () => {
    const u = await newUser();
    await grant(u, "pro_monthly", { starts: Date.now() - DAY, expires: Date.now() + 29 * DAY });
    await consumeRun(db, u); // creates the period row
    await db.prepare("UPDATE usage_periods SET allowance = 100, used = 99 WHERE user_id = ?").bind(u).run();

    const results = await Promise.all(Array.from({ length: 100 }, () => code(consumeRun(db, u))));
    expect(results.filter((r) => r === "ok")).toHaveLength(1);
    expect(results.filter((r) => r === "quota_exhausted")).toHaveLength(99);
    expect((await usage(u))?.used).toBe(100);
    const { results: made } = await db
      .prepare("SELECT r.id FROM run_reservations r JOIN usage_periods p ON p.id = r.usage_period_id WHERE p.user_id = ?")
      .bind(u).all();
    expect(made).toHaveLength(2); // the first run plus the one winner
  });

  it("parallel refunds of one reservation give back one run", async () => {
    const u = await newUser();
    const a = await consumeRun(db, u);
    await consumeRun(db, u);
    await Promise.all(Array.from({ length: 20 }, () => refundRun(db, a)));
    expect((await usage(u))?.used).toBe(1);
  });
});

describe("me identity", () => {
  it("reports the email and how the account signs in", async () => {
    const u = await newUser();
    expect(await getMe(db, u)).toMatchObject({ email: `${u}@test`, provider: "email" });
    await db.prepare("UPDATE users SET apple_sub = ?, email = ? WHERE id = ?").bind(`apple-${u}`, "x@privaterelay.appleid.com", u).run();
    expect(await getMe(db, u)).toMatchObject({ email: "x@privaterelay.appleid.com", provider: "apple" });
    await db.prepare("UPDATE users SET apple_sub = NULL, google_sub = ?, email = NULL WHERE id = ?").bind(`g-${u}`, u).run();
    expect(await getMe(db, u)).toMatchObject({ email: null, provider: "google" });
  });
});

describe("me name", () => {
  it("returns the stored name", async () => {
    const u = await newUser();
    expect((await getMe(db, u)).name).toBeNull();
    await db.prepare("UPDATE users SET name = ? WHERE id = ?").bind("Noah Nguyen", u).run();
    expect((await getMe(db, u)).name).toBe("Noah Nguyen");
  });
});
