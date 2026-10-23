// Lemon Squeezy webhooks (direct sales). Field names follow Lemon Squeezy's webhook docs; confirm them against
// real test-mode deliveries (see backend/README, "Test payments").
import { config } from "../config.ts";
import type { Deps, Env } from "./env.ts";
import { sha256Hex } from "./jwt.ts";
import { alreadyHandled, applyRenewal, grantLifetime, markHandled, refund, upsertSubscription, type ProductKind } from "./purchases.ts";

const enc = new TextEncoder();

/** X-Signature is the hex HMAC-SHA256 of the raw body with the webhook's signing secret. */
export async function verifySignature(rawBody: string, signature: string | null, secret: string): Promise<boolean> {
  if (!signature || !secret) return false;
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const expected = [...new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(rawBody)))].map((b) => b.toString(16).padStart(2, "0")).join("");
  if (expected.length !== signature.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ signature.toLowerCase().charCodeAt(i);
  return diff === 0;
}

/** Upgrade variants, tier 1 first: `LS_VARIANT_LIFETIME_UPGRADE_1` ... `_N` (config.UPGRADE_TIERS), each half the price before. */
function upgradeTier(env: Env, v: string): number {
  for (let tier = 1; tier <= config.UPGRADE_TIERS; tier++) {
    if (v === (env as unknown as Record<string, string | undefined>)[`LS_VARIANT_LIFETIME_UPGRADE_${tier}`]) return tier;
  }
  return 0;
}

function productFor(env: Env, variantId: unknown): ProductKind | null {
  const v = String(variantId ?? "");
  if (!v) return null;
  if (v === env.LS_VARIANT_LIFETIME) return "lifetime";
  if (upgradeTier(env, v)) return "lifetime_renewal";
  if (v === env.LS_VARIANT_PRO_MONTHLY) return "pro_monthly";
  if (v === env.LS_VARIANT_PRO_YEARLY) return "pro_yearly";
  return null;
}

const ms = (iso: unknown): number | null => {
  const t = typeof iso === "string" ? Date.parse(iso) : NaN;
  return Number.isNaN(t) ? null : t;
};

export type Outcome = "applied" | "ignored" | "duplicate";

/** Handles one verified delivery. Returns what happened, for logs and tests. */
export async function handleLemonSqueezy(env: Env, deps: Deps, rawBody: string): Promise<Outcome> {
  const now = deps.now();
  const key = await sha256Hex(rawBody);
  if (await alreadyHandled(env.DB, key)) return "duplicate";

  let payload: any;
  try { payload = JSON.parse(rawBody); } catch { return "ignored"; }
  const event: string = payload?.meta?.event_name ?? "";
  const data = payload?.data;
  const attrs = data?.attributes ?? {};
  if (payload?.meta?.test_mode === true && env.LS_ACCEPT_TEST_MODE !== "true") return "ignored"; // test payments must not unlock production accounts
  const userId: string | null = typeof payload?.meta?.custom_data?.user_id === "string" ? payload.meta.custom_data.user_id : null;

  let outcome: Outcome = "ignored";

  switch (event) {
    case "order_created": {
      if (attrs.status !== "paid") break;
      const product = productFor(env, attrs.first_order_item?.variant_id);
      if (product !== "lifetime" && product !== "lifetime_renewal") break; // subscription orders are handled by the subscription events
      const orderId = String(data.id);
      const tier = upgradeTier(env, String(attrs.first_order_item?.variant_id ?? ""));
      const purchasedAt = ms(attrs.created_at) ?? now;
      if (userId && (await userExists(env.DB, userId))) {
        if (product === "lifetime") { await grantLifetime(env.DB, userId, "lemonsqueezy", orderId, purchasedAt, now); outcome = "applied"; }
        else if (await applyRenewal(env.DB, userId, "lemonsqueezy", orderId, tier, now)) outcome = "applied";
      } else {
        // Bought without being signed in: kept until the buyer enters the licence key in the app (FR-P4).
        await env.DB.prepare("INSERT OR IGNORE INTO pending_licenses (order_id, source, kind, tier, email, purchased_at, created_at) VALUES (?, 'lemonsqueezy', ?, ?, ?, ?, ?)")
          .bind(orderId, product, tier || 1, typeof attrs.user_email === "string" ? attrs.user_email.toLowerCase() : null, purchasedAt, now).run();
        outcome = "applied";
      }
      break;
    }

    case "license_key_created": {
      if (typeof attrs.key !== "string" || attrs.order_id == null) break;
      await env.DB.prepare("INSERT OR IGNORE INTO license_keys (key_hash, order_id, created_at) VALUES (?, ?, ?)")
        .bind(await sha256Hex(attrs.key.trim()), String(attrs.order_id), now).run();
      outcome = "applied";
      break;
    }

    case "order_refunded": {
      // A refunded Lifetime order loses its licence. A refunded renewal cannot be rolled back (the window may have moved on).
      if (await refund(env.DB, "lemonsqueezy", String(data.id), now)) outcome = "applied";
      break;
    }

    case "subscription_payment_refunded": {
      if (attrs.subscription_id != null && (await refund(env.DB, "lemonsqueezy", String(attrs.subscription_id), now))) outcome = "applied";
      break;
    }

    default: {
      if (!event.startsWith("subscription_") || data?.type !== "subscriptions") break;
      const product = productFor(env, attrs.variant_id);
      if ((product !== "pro_monthly" && product !== "pro_yearly") || !userId || !(await userExists(env.DB, userId))) break;

      const renewsAt = ms(attrs.renews_at);
      const endsAt = ms(attrs.ends_at);
      let status: "active" | "expired" = "active";
      let expiresAt: number | null;
      switch (attrs.status) {
        case "active": case "on_trial": expiresAt = endsAt ?? renewsAt; break;           // endsAt is set once cancelled: access runs to it
        case "cancelled": expiresAt = endsAt ?? now; break;                              // cancelled: keep access until the paid period ends
        case "past_due": expiresAt = (renewsAt ?? now) + config.GRACE_DAYS * 86_400_000; break; // payment retry: grace period
        default: status = "expired"; expiresAt = endsAt ?? now;                          // paused, unpaid, expired
      }
      await upsertSubscription(env.DB, userId, "lemonsqueezy", String(data.id), {
        plan: product, status, startsAt: ms(attrs.created_at) ?? now, expiresAt, sourceUpdatedAt: ms(attrs.updated_at) ?? now,
      }, now);
      outcome = "applied";
    }
  }

  await markHandled(env.DB, "lemonsqueezy", key, now);
  return outcome;
}

async function userExists(db: D1Database, userId: string): Promise<boolean> {
  return (await db.prepare("SELECT 1 FROM users WHERE id = ?").bind(userId).first()) !== null;
}

