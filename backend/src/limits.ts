// Per-user limits (FR-B9): requests per minute and streams in flight. Both checks are single statements,
// so concurrent requests cannot slip past them.
import { config } from "../config.ts";

export async function takeRateSlot(db: D1Database, userId: string, now: number): Promise<{ ok: true } | { ok: false; retryAfter: number }> {
  const since = now - 60_000;
  const [, insert] = await db.batch([
    db.prepare("DELETE FROM rate_events WHERE user_id = ? AND at < ?").bind(userId, since),
    db.prepare(
      `INSERT INTO rate_events (user_id, at) SELECT ?, ? WHERE (SELECT COUNT(*) FROM rate_events WHERE user_id = ? AND at >= ?) < ?`,
    ).bind(userId, now, userId, since, config.RATE_LIMIT_PER_MIN),
  ]);
  if (insert.meta.changes === 1) return { ok: true };
  const oldest = await db.prepare("SELECT MIN(at) AS at FROM rate_events WHERE user_id = ? AND at >= ?").bind(userId, since).first<{ at: number | null }>();
  return { ok: false, retryAfter: Math.max(1, Math.ceil(((oldest?.at ?? now) + 60_000 - now) / 1000)) };
}

/** Streams older than the upstream timeout (plus slack) are treated as dead. */
const staleAfterMs = () => (config.UPSTREAM_TIMEOUT_S + 30) * 1000;

export async function takeStreamSlot(db: D1Database, userId: string, now: number): Promise<string | null> {
  const id = crypto.randomUUID();
  const r = await db.prepare(
    `INSERT INTO active_streams (id, user_id, started_at) SELECT ?, ?, ? WHERE (SELECT COUNT(*) FROM active_streams WHERE user_id = ? AND started_at > ?) < ?`,
  ).bind(id, userId, now, userId, now - staleAfterMs(), config.MAX_CONCURRENT_STREAMS).run();
  return r.meta.changes === 1 ? id : null;
}

export async function releaseStreamSlot(db: D1Database, id: string): Promise<void> {
  await db.prepare("DELETE FROM active_streams WHERE id = ?").bind(id).run();
}
