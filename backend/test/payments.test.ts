import { describe, expect, it } from "vitest";
import { config } from "../config.ts";
import { handleRequest } from "../src/app.ts";
import type { Deps } from "../src/env.ts";
import { b64urlEncode, signJwt } from "../src/jwt.ts";
import { getMe } from "../src/me.ts";
import { consumeRun, RunError } from "../src/metering.ts";
import { verifyAppleJws } from "../src/x509.ts";
import chain from "./fixtures/apple-test-chain.json";
import { DAY, grant, newUser, testEnv } from "./helpers.ts";

const enc = new TextEncoder();
const env = {
  ...testEnv, ANTHROPIC_API_KEY: "k", LS_WEBHOOK_SECRET: "ls-test-secret",
  LS_VARIANT_LIFETIME: "111", LS_VARIANT_LIFETIME_RENEWAL: "222", LS_VARIANT_PRO_MONTHLY: "333", LS_VARIANT_PRO_YEARLY: "444",
  APPSTORE_ENVIRONMENTS: "Production,Sandbox", LS_ACCEPT_TEST_MODE: "false",
};
let clock = Date.now();
const deps: Deps = { now: () => clock, fetch, sendEmail: async () => {}, appleRootSha256: [chain.rootSha256] };
const iso = (ms: number) => new Date(ms).toISOString();

async function call(path: string, o: { user?: string; body?: unknown; raw?: string; headers?: Record<string, string>; method?: string; e?: typeof env } = {}) {
  const headers: Record<string, string> = { ...o.headers };
  if (o.user) headers.authorization = `Bearer ${await signJwt({ sub: o.user, exp: Math.floor(clock / 1000) + 600 }, env.JWT_SECRET)}`;
  return handleRequest(new Request(`https://api.test${path}`, { method: o.method ?? "POST", headers, body: o.raw ?? (o.body === undefined ? undefined : JSON.stringify(o.body)) }), o.e ?? env, deps);
}
const me = async (user: string) => (await call("/v1/me", { user, method: "GET" })).json<any>();

// ---------- Lemon Squeezy ----------
async function sign(raw: string, secret = env.LS_WEBHOOK_SECRET) {
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return [...new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(raw)))].map((b) => b.toString(16).padStart(2, "0")).join("");
}
async function ls(event: string, data: unknown, o: { user?: string | null; test?: boolean; secret?: string } = {}) {
  const raw = JSON.stringify({ meta: { event_name: event, test_mode: o.test ?? false, custom_data: o.user ? { user_id: o.user } : {} }, data });
  const res = await call("/webhooks/lemonsqueezy", { raw, headers: { "x-signature": await sign(raw, o.secret), "x-event-name": event } });
  return { status: res.status, outcome: (await res.json<any>()).outcome as string | undefined };
}
const order = (id: string, variant: number, o: { status?: string; email?: string } = {}) =>
  ({ type: "orders", id, attributes: { status: o.status ?? "paid", created_at: iso(clock), user_email: o.email ?? "buyer@example.com", first_order_item: { variant_id: variant } } });
const sub = (id: string, variant: number, a: Record<string, unknown>) =>
  ({ type: "subscriptions", id, attributes: { variant_id: variant, status: "active", created_at: iso(clock - DAY), renews_at: iso(clock + 29 * DAY), ends_at: null, updated_at: iso(clock), ...a } });

async function trialUser() {
  const u = await newUser();
  await grant(u, "trial", { starts: clock, expires: clock + 21 * DAY });
  return u;
}

describe("Lemon Squeezy webhook", () => {
  it("rejects a bad or missing signature, and does nothing", async () => {
    const u = await newUser();
    expect((await ls("order_created", order("o1", 111), { user: u, secret: "wrong" })).status).toBe(401);
    expect((await call("/webhooks/lemonsqueezy", { raw: "{}" })).status).toBe(401);
    expect((await me(u)).owns_lifetime).toBe(false);
    expect((await call("/webhooks/lemonsqueezy", { raw: "{}", e: { ...env, LS_WEBHOOK_SECRET: undefined as any } })).status).toBe(503);
  });

  it("AC-6: a Lifetime purchase ends the trial and means bring-your-own-key", async () => {
    const u = await trialUser();
    expect((await ls("order_created", order("lt-1", 111), { user: u })).outcome).toBe("applied");
    const m = await me(u);
    expect(m).toMatchObject({ plan: "lifetime", owns_lifetime: true, runs_used: null });
    expect(Date.parse(m.updates_until)).toBeGreaterThan(clock + 360 * DAY);
    await expect(consumeRun(testEnv.DB, u, clock)).rejects.toMatchObject({ code: "byok_required" });
    const t = await testEnv.DB.prepare("SELECT status FROM entitlements WHERE user_id = ? AND plan = 'trial'").bind(u).first<{ status: string }>();
    expect(t?.status).toBe("expired");   // unused credits dropped
  });

  it("an identical delivery twice, or an unpaid order, changes nothing", async () => {
    const u = await newUser();
    const raw = { user: u };
    expect((await ls("order_created", order("lt-2", 111), raw)).outcome).toBe("applied");
    expect((await ls("order_created", order("lt-2", 111), raw)).outcome).toBe("duplicate");
    expect((await ls("order_created", order("lt-3", 111, { status: "pending" }), raw)).outcome).toBe("ignored");
    const n = await testEnv.DB.prepare("SELECT COUNT(*) AS n FROM entitlements WHERE user_id = ? AND plan = 'lifetime'").bind(u).first<{ n: number }>();
    expect(n?.n).toBe(1);
  });

  it("AC-8: subscribing to Pro Yearly ends the trial and gives the monthly allowance", async () => {
    const u = await trialUser();
    expect((await ls("subscription_created", sub("sub-1", 444, {}), { user: u })).outcome).toBe("applied");
    const m = await me(u);
    expect(m).toMatchObject({ plan: "pro_yearly", runs_allowance: config.PRO_MONTHLY_RUNS, runs_used: 0 });
    expect(Date.parse(m.period_end)).toBeGreaterThan(clock);
    await consumeRun(testEnv.DB, u, clock);
    expect((await me(u)).runs_used).toBe(1);
  });

  it("AC-10: cancelling keeps access until the period ends, then falls back", async () => {
    const u = await newUser();
    await ls("order_created", order("lt-4", 111), { user: u });
    await ls("subscription_created", sub("sub-2", 333, { status: "active" }), { user: u });
    expect((await me(u)).plan).toBe("pro_monthly");

    const endsAt = clock + 10 * DAY;
    await ls("subscription_cancelled", sub("sub-2", 333, { status: "cancelled", ends_at: iso(endsAt), updated_at: iso(clock + 1000) }), { user: u });
    expect((await me(u)).plan).toBe("pro_monthly");                       // still paid for
    clock += 11 * DAY;
    expect((await me(u)).plan).toBe("lifetime");                          // lapsed: falls back to Lifetime (BYOK)
    const solo = await newUser();
    await ls("subscription_created", sub("sub-3", 333, { status: "cancelled", ends_at: iso(clock - DAY) }), { user: solo });
    expect((await me(solo)).plan).toBe("none");
    clock = Date.now();
  });

  it("renewal moves the paid-through date but not the allowance anchor", async () => {
    const u = await newUser();
    await ls("subscription_created", sub("sub-4", 333, { created_at: iso(clock - 40 * DAY), renews_at: iso(clock + 20 * DAY) }), { user: u });
    const before = await testEnv.DB.prepare("SELECT starts_at, expires_at FROM entitlements WHERE user_id = ?").bind(u).first<any>();
    await ls("subscription_updated", sub("sub-4", 333, { created_at: iso(clock - 40 * DAY), renews_at: iso(clock + 50 * DAY), updated_at: iso(clock + 5000) }), { user: u });
    const after = await testEnv.DB.prepare("SELECT starts_at, expires_at FROM entitlements WHERE user_id = ?").bind(u).first<any>();
    expect(after.starts_at).toBe(before.starts_at);
    expect(after.expires_at).toBeGreaterThan(before.expires_at);
  });

  it("a payment retry keeps access for the grace period, then it lapses", async () => {
    const u = await newUser();
    await ls("subscription_created", sub("sub-5", 333, { status: "past_due", renews_at: iso(clock - DAY), updated_at: iso(clock) }), { user: u });
    expect((await me(u)).plan).toBe("pro_monthly");
    clock += (config.GRACE_DAYS + 1) * DAY;
    expect((await me(u)).plan).toBe("none");
    clock = Date.now();
    await ls("subscription_expired", sub("sub-5", 333, { status: "expired", ends_at: iso(clock), updated_at: iso(clock + 9000) }), { user: u });
    expect((await me(u)).plan).toBe("none");
  });

  it("a stale event cannot undo a newer one", async () => {
    const u = await newUser();
    await ls("subscription_updated", sub("sub-6", 333, { status: "expired", ends_at: iso(clock), updated_at: iso(clock + 10_000) }), { user: u });
    await ls("subscription_updated", sub("sub-6", 333, { status: "active", updated_at: iso(clock - 10_000) }), { user: u });
    expect((await me(u)).plan).toBe("none");
  });

  it("refunds take the entitlement away, and a replayed order does not bring it back", async () => {
    const u = await newUser();
    await ls("order_created", order("lt-5", 111), { user: u });
    expect((await ls("order_refunded", { type: "orders", id: "lt-5", attributes: {} }, { user: u })).outcome).toBe("applied");
    expect((await me(u)).plan).toBe("none");
    await grant(u, "pro_monthly", { starts: clock - DAY, expires: clock + 20 * DAY });
    await ls("subscription_created", sub("sub-7", 333, {}), { user: u });
    await ls("subscription_payment_refunded", { type: "subscription-invoices", id: "inv", attributes: { subscription_id: 7 } }, { user: u });
    // the subscription above used id sub-7, the refund names 7: only the matching one is revoked
    const row = await testEnv.DB.prepare("SELECT status FROM entitlements WHERE external_id = 'sub-7'").first<{ status: string }>();
    expect(row?.status).toBe("active");
    await ls("subscription_payment_refunded", { type: "subscription-invoices", id: "inv2", attributes: { subscription_id: "sub-7" } }, { user: u });
    expect((await testEnv.DB.prepare("SELECT status FROM entitlements WHERE external_id = 'sub-7'").first<{ status: string }>())?.status).toBe("refunded");
    await ls("order_created", { ...order("lt-5", 111), attributes: { ...order("lt-5", 111).attributes, user_email: "again@example.com" } }, { user: u });
    expect((await testEnv.DB.prepare("SELECT status FROM entitlements WHERE external_id = 'lt-5'").first<{ status: string }>())?.status).toBe("refunded");
  });

  it("an update renewal adds 12 months once, even if the order is delivered twice in different words", async () => {
    const u = await newUser();
    await ls("order_created", order("lt-6", 111), { user: u });
    const first = Date.parse((await me(u)).updates_until);
    expect((await ls("order_created", order("rn-1", 222), { user: u })).outcome).toBe("applied");
    const second = Date.parse((await me(u)).updates_until);
    expect(second).toBeGreaterThan(first + 300 * DAY);
    await ls("order_created", order("rn-1", 222, { email: "other@example.com" }), { user: u });
    expect(Date.parse((await me(u)).updates_until)).toBe(second);
    expect((await ls("order_created", order("rn-2", 222), { user: await newUser() })).outcome).toBe("ignored"); // nothing to renew
  });

  it("test-mode payments are ignored unless this deployment accepts them", async () => {
    const u = await newUser();
    expect((await ls("order_created", order("t-1", 111), { user: u, test: true })).outcome).toBe("ignored");
    expect((await me(u)).owns_lifetime).toBe(false);
  });

  it("an order for an unknown variant or user changes nothing", async () => {
    const u = await newUser();
    expect((await ls("order_created", order("x-1", 999), { user: u })).outcome).toBe("ignored");
    expect((await ls("subscription_created", sub("x-2", 333, {}), { user: crypto.randomUUID() })).outcome).toBe("ignored");
  });
});

describe("licence keys (FR-P4)", () => {
  async function guestPurchase(orderId: string, key: string) {
    await ls("order_created", order(orderId, 111), { user: null });
    await ls("license_key_created", { type: "license-keys", id: `lk-${orderId}`, attributes: { key, order_id: orderId } });
  }

  it("someone who bought before signing in links the purchase with the key", async () => {
    await guestPurchase("g-1", "AAAA-BBBB-CCCC-1111");
    const u = await newUser();
    expect((await me(u)).owns_lifetime).toBe(false);
    const res = await call("/v1/license/activate", { user: u, body: { license_key: "AAAA-BBBB-CCCC-1111" } });
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ plan: "lifetime", owns_lifetime: true });
    expect((await call("/v1/license/activate", { user: u, body: { license_key: " AAAA-BBBB-CCCC-1111 " } })).status).toBe(200);   // same account: fine
    expect((await call("/v1/license/activate", { user: await newUser(), body: { license_key: "AAAA-BBBB-CCCC-1111" } })).status).toBe(409);
  });

  it("a key bought while signed in belongs to that account", async () => {
    const buyer = await newUser();
    await ls("order_created", order("g-2", 111), { user: buyer });
    await ls("license_key_created", { type: "license-keys", id: "lk2", attributes: { key: "DDDD-EEEE-FFFF-2222", order_id: "g-2" } });
    expect((await call("/v1/license/activate", { user: buyer, body: { license_key: "DDDD-EEEE-FFFF-2222" } })).status).toBe(200);
    expect((await call("/v1/license/activate", { user: await newUser(), body: { license_key: "DDDD-EEEE-FFFF-2222" } })).status).toBe(409);
  });

  it("two accounts racing for one key: exactly one wins", async () => {
    await guestPurchase("g-3", "RACE-RACE-RACE-3333");
    const users = await Promise.all(Array.from({ length: 8 }, () => newUser()));
    const results = await Promise.all(users.map((u) => call("/v1/license/activate", { user: u, body: { license_key: "RACE-RACE-RACE-3333" } })));
    expect(results.filter((r) => r.status === 200)).toHaveLength(1);
    expect(results.filter((r) => r.status === 409)).toHaveLength(7);
  });

  it("unknown keys, bad input and no sign-in are refused; keys are stored hashed", async () => {
    const u = await newUser();
    expect((await call("/v1/license/activate", { user: u, body: { license_key: "NOPE-NOPE-NOPE-0000" } })).status).toBe(404);
    expect((await call("/v1/license/activate", { user: u, body: { license_key: "x" } })).status).toBe(400);
    expect((await call("/v1/license/activate", { body: { license_key: "AAAA-BBBB-CCCC-1111" } })).status).toBe(401);
    await guestPurchase("g-4", "HASH-HASH-HASH-4444");
    const stored = await testEnv.DB.prepare("SELECT key_hash FROM license_keys WHERE order_id = 'g-4'").first<{ key_hash: string }>();
    expect(stored?.key_hash).not.toContain("HASH-HASH");
  });
});

// ---------- Mac App Store ----------
const b64 = (s: string) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
const leafKey = crypto.subtle.importKey("pkcs8", b64(chain.leafKeyPkcs8), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);

async function jws(payload: Record<string, unknown>, x5c = [chain.leaf, chain.intermediate, chain.root]) {
  const head = b64urlEncode(enc.encode(JSON.stringify({ alg: "ES256", x5c })));
  const body = b64urlEncode(enc.encode(JSON.stringify(payload)));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, await leafKey, enc.encode(`${head}.${body}`));
  return `${head}.${body}.${b64urlEncode(sig)}`;
}
const txn = (user: string | null, o: Record<string, unknown> = {}) => ({
  bundleId: config.BUNDLE_ID, environment: "Sandbox", productId: "pro_yearly", transactionId: String(Math.floor(Math.random() * 1e12)),
  originalTransactionId: "orig-1", purchaseDate: clock, originalPurchaseDate: clock - DAY, expiresDate: clock + 364 * DAY, signedDate: clock,
  appAccountToken: user, ...o,
});
const submit = async (user: string, payload: Record<string, unknown>) =>
  call("/v1/purchases/storekit", { user, body: { signed_transaction: await jws(payload) } });

describe("App Store signature checks", () => {
  const roots = [chain.rootSha256];
  it("accepts a correctly chained JWS and returns its payload", async () => {
    expect(await verifyAppleJws(await jws({ hello: "world" }), roots, clock)).toEqual({ hello: "world" });
  });

  it("refuses an untrusted root, a missing marker, an expired chain, a tampered payload and a short chain", async () => {
    const good = await jws({ a: 1 });
    await expect(verifyAppleJws(good, ["0".repeat(64)], clock)).rejects.toThrow(/not trusted/);
    await expect(verifyAppleJws(await jws({ a: 1 }, [chain.leafWithoutMarker, chain.intermediate, chain.root]), roots, clock)).rejects.toThrow(/not an Apple/);
    await expect(verifyAppleJws(await jws({ a: 1 }, [chain.leaf, chain.intermediate, chain.rogueRoot]), [chain.rogueRootSha256], clock)).rejects.toThrow(/signature is invalid|chain is broken/);
    await expect(verifyAppleJws(good, roots, clock + 400 * DAY)).rejects.toThrow(/not valid now/);
    const [h, , s] = good.split(".");
    await expect(verifyAppleJws(`${h}.${b64urlEncode(enc.encode('{"a":2}'))}.${s}`, roots, clock)).rejects.toThrow(/signature is invalid/);
    await expect(verifyAppleJws(await jws({ a: 1 }, [chain.leaf, chain.intermediate]), roots, clock)).rejects.toThrow(/chain length/);
    await expect(verifyAppleJws("a.b", roots, clock)).rejects.toThrow();
  });

  it("the pinned root in config is Apple Root CA - G3", () => {
    expect(config.APPLE_ROOT_SHA256).toBe("63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179");
  });
});

describe("POST /v1/purchases/storekit", () => {
  it("AC-8: a Pro Yearly purchase unlocks the plan and ends the trial", async () => {
    const u = await trialUser();
    const res = await submit(u, txn(u));
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ plan: "pro_yearly", runs_allowance: config.PRO_MONTHLY_RUNS });
  });

  it("AC-6: a Lifetime purchase gives the licence", async () => {
    const u = await trialUser();
    await submit(u, txn(u, { productId: "lifetime_byok", originalTransactionId: "lt-sk-1", expiresDate: undefined }));
    expect(await me(u)).toMatchObject({ plan: "lifetime", owns_lifetime: true });
  });

  it("AC-13: the same purchase restored on another Mac, same account, shows the same plan; resending is harmless", async () => {
    const u = await newUser();
    const t = txn(u, { productId: "lifetime_byok", originalTransactionId: "lt-sk-2", expiresDate: undefined });
    await submit(u, t);
    await submit(u, t);
    const n = await testEnv.DB.prepare("SELECT COUNT(*) AS n FROM entitlements WHERE user_id = ? AND plan = 'lifetime'").bind(u).first<{ n: number }>();
    expect(n?.n).toBe(1);
    expect(await me(u)).toMatchObject({ plan: "lifetime" });     // device B signs in and just asks the server
  });

  it("refuses a purchase that belongs to someone else, another app, or a foreign environment", async () => {
    const a = await newUser(), b = await newUser();
    expect((await submit(b, txn(a))).status).toBe(409);
    expect((await me(b)).plan).toBe("none");
    expect((await submit(a, txn(a, { bundleId: "com.someone.else" }))).status).toBe(400);
    expect((await submit(a, txn(a, { productId: "free_gems" }))).status).toBe(400);
    expect((await call("/v1/purchases/storekit", { user: a, body: { signed_transaction: await jws(txn(a, { environment: "Sandbox" })) }, e: { ...env, APPSTORE_ENVIRONMENTS: "Production" } })).status).toBe(400);
    expect((await call("/v1/purchases/storekit", { user: a, body: { signed_transaction: "not.a.jws" } })).status).toBe(400);
    expect((await call("/v1/purchases/storekit", { body: { signed_transaction: await jws(txn(a)) } })).status).toBe(401);
    expect((await me(a)).plan).toBe("none");
  });

  it("a revoked transaction is a refund; an update renewal applies once per transaction", async () => {
    const u = await newUser();
    await submit(u, txn(u, { productId: "lifetime_byok", originalTransactionId: "lt-sk-3", expiresDate: undefined }));
    await submit(u, txn(u, { productId: "lifetime_renewal", transactionId: "rn-sk-1", expiresDate: undefined }));
    const once = Date.parse((await me(u)).updates_until);
    await submit(u, txn(u, { productId: "lifetime_renewal", transactionId: "rn-sk-1", expiresDate: undefined }));
    expect(Date.parse((await me(u)).updates_until)).toBe(once);
    await submit(u, txn(u, { productId: "lifetime_byok", originalTransactionId: "lt-sk-3", expiresDate: undefined, revocationDate: clock }));
    expect((await me(u)).plan).toBe("none");
  });
});

describe("POST /webhooks/appstore", () => {
  const notify = async (type: string, tx: Record<string, unknown>, o: { subtype?: string; id?: string; renewal?: Record<string, unknown> } = {}) => {
    const outer = {
      notificationType: type, subtype: o.subtype, notificationUUID: o.id ?? crypto.randomUUID(), signedDate: clock,
      data: { bundleId: config.BUNDLE_ID, environment: "Sandbox", signedTransactionInfo: await jws(tx), ...(o.renewal ? { signedRenewalInfo: await jws(o.renewal) } : {}) },
    };
    const res = await call("/webhooks/appstore", { body: { signedPayload: await jws(outer) } });
    return { status: res.status, outcome: (await res.json<any>()).outcome as string | undefined };
  };

  it("renewals extend the subscription; AC-10: access lasts to the paid-through date; duplicates are skipped", async () => {
    const u = await newUser();
    await submit(u, txn(u, { originalTransactionId: "sub-sk-1", expiresDate: clock + 5 * DAY }));
    const id = crypto.randomUUID();
    expect(await notify("DID_RENEW", txn(u, { originalTransactionId: "sub-sk-1", expiresDate: clock + 35 * DAY, signedDate: clock + 1000 }), { id })).toMatchObject({ status: 200, outcome: "applied" });
    expect((await notify("DID_RENEW", txn(u, { originalTransactionId: "sub-sk-1", expiresDate: clock + 35 * DAY }), { id })).outcome).toBe("duplicate");
    clock += 30 * DAY;
    expect((await me(u)).plan).toBe("pro_yearly");
    clock += 6 * DAY;
    expect((await me(u)).plan).toBe("none");
    clock = Date.now();
  });

  it("a refund or revocation removes access", async () => {
    const u = await newUser();
    await submit(u, txn(u, { originalTransactionId: "sub-sk-2" }));
    expect((await me(u)).plan).toBe("pro_yearly");
    expect((await notify("REFUND", txn(u, { originalTransactionId: "sub-sk-2", signedDate: clock + 1000 }))).outcome).toBe("applied");
    expect((await me(u)).plan).toBe("none");
  });

  it("a billing retry in its grace period keeps access", async () => {
    const u = await newUser();
    await submit(u, txn(u, { originalTransactionId: "sub-sk-3", expiresDate: clock - DAY }));
    expect((await me(u)).plan).toBe("none");
    await notify("DID_FAIL_TO_RENEW", txn(u, { originalTransactionId: "sub-sk-3", expiresDate: clock - DAY, signedDate: clock + 1000 }), { subtype: "GRACE_PERIOD" });
    expect((await me(u)).plan).toBe("pro_yearly");
  });

  it("a transaction with no account token is acknowledged and ignored; forged payloads are refused", async () => {
    expect((await notify("DID_RENEW", txn(null, { originalTransactionId: "anon" }))).outcome).toBe("ignored");
    const forged = { notificationType: "REFUND", notificationUUID: "x", data: { bundleId: config.BUNDLE_ID } };
    const head = b64urlEncode(enc.encode(JSON.stringify({ alg: "ES256", x5c: [chain.leaf, chain.intermediate, chain.root] })));
    const res = await call("/webhooks/appstore", { body: { signedPayload: `${head}.${b64urlEncode(enc.encode(JSON.stringify(forged)))}.${b64urlEncode(new Uint8Array(64))}` } });
    expect(res.status).toBe(400);
    expect((await call("/webhooks/appstore", { body: {} })).status).toBe(400);
  });
});

describe("limits of RunError mapping stay intact", () => {
  it("Pro from the App Store meters like any Pro", async () => {
    const u = await newUser();
    await submit(u, txn(u, { originalTransactionId: "sub-sk-4" }));
    await consumeRun(testEnv.DB, u, clock);
    await expect(consumeRun(testEnv.DB, await newUser(), clock)).rejects.toBeInstanceOf(RunError);
    expect((await getMe(testEnv.DB, u, clock)).runs_used).toBe(1);
  });
});
