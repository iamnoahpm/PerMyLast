// Mac App Store purchases: signed transactions from the app (StoreKit 2) and App Store Server Notifications V2.
// Both carry Apple-signed JWS; both end in the same grant. The buyer is identified by `appAccountToken`, which the
// app sets to the user's id when it starts a purchase (FR-P2).
import { config } from "../config.ts";
import type { Deps, Env } from "./env.ts";
import { alreadyHandled, applyRenewal, grantLifetime, markHandled, refund, upsertSubscription, type ProductKind } from "./purchases.ts";
import { verifyAppleJws } from "./x509.ts";

/** StoreKit product ids (PRD section 7). */
const PRODUCTS: Record<string, ProductKind> = {
  lifetime_byok: "lifetime",
  pro_monthly: "pro_monthly",
  pro_yearly: "pro_yearly",
};

/** Upgrade ladder: `lifetime_upgrade_1` ... `_N`, each priced at half the one before (config.UPGRADE_TIERS). */
const UPGRADES: Record<string, number> = Object.fromEntries(
  Array.from({ length: config.UPGRADE_TIERS }, (_, i) => [`lifetime_upgrade_${i + 1}`, i + 1]),
);

export class AppStoreError extends Error {
  constructor(readonly code: "invalid_receipt" | "wrong_account" | "unknown_product", message: string) { super(message); }
}

const environments = (env: Env) => (env.APPSTORE_ENVIRONMENTS ?? "Production").split(",").map((s) => s.trim());

/** Verifies a JWS or throws AppStoreError. */
async function verified(jws: unknown, deps: Deps): Promise<Record<string, any>> {
  if (typeof jws !== "string") throw new AppStoreError("invalid_receipt", "Missing signed data.");
  try {
    return await verifyAppleJws(jws, deps.appleRootSha256 ?? [config.APPLE_ROOT_SHA256], deps.now());
  } catch (error) {
    throw new AppStoreError("invalid_receipt", error instanceof Error ? error.message : "Invalid signed data.");
  }
}

interface Applied { applied: boolean; plan: ProductKind }

/** Applies a verified transaction payload to an account. `expectedUser` is checked against the transaction's account token. */
async function applyTransaction(env: Env, tx: Record<string, any>, expectedUser: string | null, now: number): Promise<Applied> {
  if (tx.bundleId !== config.BUNDLE_ID) throw new AppStoreError("invalid_receipt", "Transaction is for a different app.");
  if (!environments(env).includes(String(tx.environment))) throw new AppStoreError("invalid_receipt", "Transaction environment is not accepted here.");
  const tier = UPGRADES[String(tx.productId)];
  const product = tier ? "lifetime_renewal" : PRODUCTS[String(tx.productId)];
  if (!product) throw new AppStoreError("unknown_product", "Unknown product.");

  const token = typeof tx.appAccountToken === "string" ? tx.appAccountToken.toLowerCase() : null;
  const userId = token ?? expectedUser?.toLowerCase() ?? null;
  if (!userId) throw new AppStoreError("wrong_account", "This purchase is not linked to an account.");
  if (expectedUser && token && token !== expectedUser.toLowerCase()) throw new AppStoreError("wrong_account", "This purchase belongs to a different account.");
  if (!(await env.DB.prepare("SELECT 1 FROM users WHERE id = ?").bind(userId).first())) throw new AppStoreError("wrong_account", "No such account.");

  const purchasedAt = Number(tx.purchaseDate ?? tx.signedDate ?? now);
  const originalId = String(tx.originalTransactionId ?? tx.transactionId);
  const revoked = tx.revocationDate != null;

  switch (product) {
    case "lifetime":
      if (revoked) return { applied: await refund(env.DB, "storekit", originalId, now), plan: product };
      await grantLifetime(env.DB, userId, "storekit", originalId, purchasedAt, now);
      return { applied: true, plan: product };
    case "lifetime_renewal":
      return { applied: !revoked && (await applyRenewal(env.DB, userId, "storekit", String(tx.transactionId), tier, now)), plan: product };
    default: {
      const expiresAt = tx.expiresDate != null ? Number(tx.expiresDate) : null;
      await upsertSubscription(env.DB, userId, "storekit", originalId, {
        plan: product, status: revoked ? "refunded" : "active",
        startsAt: Number(tx.originalPurchaseDate ?? purchasedAt), expiresAt,
        sourceUpdatedAt: Number(tx.signedDate ?? purchasedAt),
      }, now);
      return { applied: true, plan: product };
    }
  }
}

/** POST /v1/purchases/storekit: the app sends the signed transaction after a purchase, and again on "Restore purchases" (FR-A18). */
export async function submitTransaction(env: Env, deps: Deps, userId: string, signedTransaction: unknown): Promise<Applied> {
  const now = deps.now();
  const tx = await verified(signedTransaction, deps);
  return await applyTransaction(env, tx, userId, now);
}

/** POST /webhooks/appstore: renewals, cancellations, refunds and billing retries while the app is closed (FR-P5). */
export async function handleAppStoreNotification(env: Env, deps: Deps, body: unknown): Promise<"applied" | "ignored" | "duplicate"> {
  const now = deps.now();
  const outer = await verified((body as { signedPayload?: unknown } | null)?.signedPayload, deps);
  const key = typeof outer.notificationUUID === "string" ? `appstore:${outer.notificationUUID}` : null;
  if (!key) throw new AppStoreError("invalid_receipt", "Notification has no id.");
  if (await alreadyHandled(env.DB, key)) return "duplicate";

  const data = outer.data ?? {};
  if (data.bundleId !== config.BUNDLE_ID) throw new AppStoreError("invalid_receipt", "Notification is for a different app.");
  let outcome: "applied" | "ignored" = "ignored";

  if (data.signedTransactionInfo) {
    const tx = await verified(data.signedTransactionInfo, deps);
    tx.environment ??= data.environment;
    const type = String(outer.notificationType ?? "");
    const subtype = String(outer.subtype ?? "");
    if (type === "REFUND" || type === "REVOKE") tx.revocationDate ??= now;
    // Billing retry: keep access a little longer while Apple retries the payment (FR-P5).
    if (type === "DID_FAIL_TO_RENEW" && subtype === "GRACE_PERIOD") {
      const renewal = data.signedRenewalInfo ? await verified(data.signedRenewalInfo, deps) : {};
      const graceEnds = Number(renewal.gracePeriodExpiresDate ?? 0) || Number(tx.expiresDate ?? now) + config.GRACE_DAYS * 86_400_000;
      tx.expiresDate = Math.max(Number(tx.expiresDate ?? 0), graceEnds);
    }
    try {
      const r = await applyTransaction(env, tx, null, now);
      if (r.applied) outcome = "applied";
    } catch (error) {
      // A transaction we cannot link to an account (no account token) is not an error worth Apple retrying for days.
      if (!(error instanceof AppStoreError && (error.code === "wrong_account" || error.code === "unknown_product"))) throw error;
    }
  }
  await markHandled(env.DB, "appstore", key, now);
  return outcome;
}
