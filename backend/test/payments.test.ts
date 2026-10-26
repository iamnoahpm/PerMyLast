import { describe, expect, it } from "vitest";
import { config } from "../config.ts";
import { handleRequest } from "../src/app.ts";
import type { Deps } from "../src/env.ts";
import { b64urlEncode, signJwt } from "../src/jwt.ts";
import { getMe } from "../src/me.ts";
import { consumeRun, RunError } from "../src/metering.ts";
import { verifyAppleJws } from "../src/x509.ts";
import chain from "./fixtures/apple-test-chain.json";
import { DAY, grant, newUser as claimedUser, testEnv } from "./helpers.ts";
const newUser = () => claimedUser(false);

const enc = new TextEncoder();
const env = {
  ...testEnv, ANTHROPIC_API_KEY: "k", APPSTORE_ENVIRONMENTS: "Production,Sandbox",
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

/** Accounts here start without the Free plan unless a test asks for it, so "none" still means "nothing bought". */
async function freeUser() {
  return claimedUser(true);
}

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
  it("AC-8: a Pro Yearly purchase unlocks the plan and replaces Free", async () => {
    const u = await freeUser();
    const res = await submit(u, txn(u));
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ plan: "pro_yearly", runs_allowance: config.PRO_MONTHLY_RUNS });
  });

  it("a free-trial transaction grants Pro until the trial ends, with no extra cap", async () => {
    const u = await freeUser();
    const res = await submit(u, txn(u, { originalTransactionId: "trial-sk-1", offerType: 1, offerDiscountType: "FREE_TRIAL", expiresDate: clock + 14 * DAY }));
    expect(res.status).toBe(200);
    const m = await me(u);
    expect(m).toMatchObject({ plan: "pro_yearly", runs_allowance: config.PRO_MONTHLY_RUNS });
    clock += 15 * DAY;                                                    // trial over, never converted: back to Free
    expect((await me(u)).plan).toBe("free");
  });

  it("AC-6: a Lifetime purchase gives the licence", async () => {
    const u = await freeUser();
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
    await submit(u, txn(u, { productId: "lifetime_upgrade_1", transactionId: "rn-sk-1", expiresDate: undefined }));
    const once = Date.parse((await me(u)).updates_until);
    await submit(u, txn(u, { productId: "lifetime_upgrade_1", transactionId: "rn-sk-1", expiresDate: undefined }));
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
