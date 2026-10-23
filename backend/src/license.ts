// POST /v1/license/activate: links a Lemon Squeezy licence key to the signed-in account (FR-P4), for people who
// bought before signing in. Idempotent for the same account; a key already linked to someone else is refused.
import type { Env } from "./env.ts";
import { sha256Hex } from "./jwt.ts";
import { applyRenewal, grantLifetime } from "./purchases.ts";

export type ActivateResult = { ok: true } | { ok: false; reason: "unknown_license" | "license_already_used" };

export async function activateLicense(env: Env, userId: string, licenseKey: string, now: number): Promise<ActivateResult> {
  const key = await env.DB.prepare("SELECT order_id FROM license_keys WHERE key_hash = ?").bind(await sha256Hex(licenseKey.trim())).first<{ order_id: string }>();
  if (!key) return { ok: false, reason: "unknown_license" };

  const pending = await env.DB.prepare("SELECT kind, tier, purchased_at, claimed_by FROM pending_licenses WHERE order_id = ?")
    .bind(key.order_id).first<{ kind: "lifetime" | "lifetime_renewal"; tier: number; purchased_at: number; claimed_by: string | null }>();

  if (pending) {
    if (pending.claimed_by && pending.claimed_by !== userId) return { ok: false, reason: "license_already_used" };
    if (!pending.claimed_by) {
      const claim = await env.DB.prepare("UPDATE pending_licenses SET claimed_by = ? WHERE order_id = ? AND claimed_by IS NULL").bind(userId, key.order_id).run();
      if (claim.meta.changes !== 1) {
        const now2 = await env.DB.prepare("SELECT claimed_by FROM pending_licenses WHERE order_id = ?").bind(key.order_id).first<{ claimed_by: string | null }>();
        if (now2?.claimed_by !== userId) return { ok: false, reason: "license_already_used" };
        return { ok: true };
      }
      if (pending.kind === "lifetime") await grantLifetime(env.DB, userId, "lemonsqueezy", key.order_id, pending.purchased_at, now);
      else await applyRenewal(env.DB, userId, "lemonsqueezy", key.order_id, pending.tier, now);
    }
    return { ok: true };
  }

  // The order was already attached to an account when it was paid (the buyer was signed in).
  const owner = await env.DB.prepare("SELECT user_id FROM entitlements WHERE source = 'lemonsqueezy' AND external_id = ?").bind(key.order_id).first<{ user_id: string }>();
  if (!owner) return { ok: false, reason: "unknown_license" };
  return owner.user_id === userId ? { ok: true } : { ok: false, reason: "license_already_used" };
}
