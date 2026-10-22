// What a purchase does to an account. Both payment channels end up here, and every function is safe to call twice.
import { config } from "../config.ts";
import { addMonths } from "./plans.ts";

export type Source = "lemonsqueezy" | "storekit";
export type ProductKind = "lifetime" | "lifetime_renewal" | "pro_monthly" | "pro_yearly";

/** Buying anything ends the trial at once; unused credits are dropped (PRD section 2). */
function endTrial(db: D1Database, userId: string, now: number): D1PreparedStatement {
  return db.prepare("UPDATE entitlements SET status = 'expired', updated_at = ? WHERE user_id = ? AND plan = 'trial' AND status = 'active'").bind(now, userId);
}

/** Lifetime licence: never expires, updates for 12 months from purchase. */
export async function grantLifetime(db: D1Database, userId: string, source: Source, externalId: string, purchasedAt: number, now: number): Promise<void> {
  const updatesUntil = addMonths(purchasedAt, config.UPDATE_WINDOW_MONTHS);
  await db.batch([
    db.prepare(
      `INSERT INTO entitlements (id, user_id, plan, status, starts_at, expires_at, updates_until, source, external_id, updated_at, source_updated_at)
       VALUES (?, ?, 'lifetime', 'active', ?, NULL, ?, ?, ?, ?, ?)
       ON CONFLICT (source, external_id) WHERE external_id IS NOT NULL DO UPDATE SET
         status = 'active', updates_until = MAX(COALESCE(entitlements.updates_until, 0), excluded.updates_until), updated_at = excluded.updated_at
       WHERE entitlements.status <> 'refunded'`, // a refunded order stays refunded if its delivery is replayed
    ).bind(crypto.randomUUID(), userId, purchasedAt, updatesUntil, source, externalId, now, purchasedAt),
    endTrial(db, userId, now),
  ]);
}

/** Update renewal: extends the Lifetime update window by 12 months from today or from its end, whichever is later. Once per order. */
export async function applyRenewal(db: D1Database, userId: string, source: Source, orderId: string, now: number): Promise<boolean> {
  const mark = await db.prepare("INSERT OR IGNORE INTO applied_purchases (source, external_id, applied_at) VALUES (?, ?, ?)").bind(source, orderId, now).run();
  if (mark.meta.changes !== 1) return false; // already applied
  const current = await db
    .prepare("SELECT id, updates_until FROM entitlements WHERE user_id = ? AND plan = 'lifetime' AND status = 'active' ORDER BY starts_at DESC LIMIT 1")
    .bind(userId).first<{ id: string; updates_until: number | null }>();
  if (!current) {
    await db.prepare("DELETE FROM applied_purchases WHERE source = ? AND external_id = ?").bind(source, orderId).run();
    return false; // a renewal without a licence: nothing to extend
  }
  await db.prepare("UPDATE entitlements SET updates_until = ?, updated_at = ? WHERE id = ?")
    .bind(addMonths(Math.max(now, current.updates_until ?? 0), config.UPDATE_WINDOW_MONTHS), now, current.id).run();
  return true;
}

export interface SubscriptionState {
  plan: "pro_monthly" | "pro_yearly";
  status: "active" | "expired" | "refunded";
  /** Anchor of the monthly allowance. Set once, never moved by renewals. */
  startsAt: number;
  /** Paid-through date (or end of the access that remains after a cancellation). */
  expiresAt: number | null;
  /** The provider's timestamp for this state; older ones are ignored. */
  sourceUpdatedAt: number;
}

export async function upsertSubscription(db: D1Database, userId: string, source: Source, externalId: string, s: SubscriptionState, now: number): Promise<void> {
  const statements = [
    db.prepare(
      `INSERT INTO entitlements (id, user_id, plan, status, starts_at, expires_at, updates_until, source, external_id, updated_at, source_updated_at)
       VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?)
       ON CONFLICT (source, external_id) WHERE external_id IS NOT NULL DO UPDATE SET
         plan = excluded.plan, status = excluded.status, expires_at = excluded.expires_at,
         updated_at = excluded.updated_at, source_updated_at = excluded.source_updated_at
       WHERE excluded.source_updated_at >= COALESCE(entitlements.source_updated_at, 0)`,
    ).bind(crypto.randomUUID(), userId, s.plan, s.status, s.startsAt, s.expiresAt, source, externalId, now, s.sourceUpdatedAt),
  ];
  if (s.status === "active") statements.push(endTrial(db, userId, now));
  await db.batch(statements);
}

/** A refund takes the entitlement away (FR-P5). */
export async function refund(db: D1Database, source: Source, externalId: string, now: number): Promise<boolean> {
  const r = await db.prepare("UPDATE entitlements SET status = 'refunded', updated_at = ? WHERE source = ? AND external_id = ? AND status <> 'refunded'")
    .bind(now, source, externalId).run();
  return r.meta.changes > 0;
}

/** Webhook deliveries are recorded after they are applied, so a failed attempt is retried, not lost. */
export async function alreadyHandled(db: D1Database, eventKey: string): Promise<boolean> {
  return (await db.prepare("SELECT 1 FROM webhook_events WHERE event_key = ?").bind(eventKey).first()) !== null;
}

export async function markHandled(db: D1Database, source: string, eventKey: string, now: number): Promise<void> {
  await db.prepare("INSERT OR IGNORE INTO webhook_events (event_key, source, received_at) VALUES (?, ?, ?)").bind(eventKey, source, now).run();
}
