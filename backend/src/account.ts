// DELETE /v1/account: erases the signed-in account and everything stored about it (App Store guideline 5.1.1(v)).
// Foreign keys cascade to sessions, profile, entitlements, usage periods and usage events. What is left is not linked
// to the person: the Apple/Google subject goes with the user row, and the install-id hash is kept in `deleted_installs`
// only so that deleting and re-creating an account cannot be used to claim the Free credits again on the same Mac.
export async function deleteAccount(db: D1Database, userId: string, now: number): Promise<void> {
  const user = await db.prepare("SELECT email FROM users WHERE id = ?").bind(userId).first<{ email: string | null }>();
  if (!user) return;
  await db.batch([
    db.prepare("INSERT OR IGNORE INTO deleted_installs (install_id_hash, deleted_at) SELECT install_id_hash, ? FROM profiles WHERE user_id = ? AND install_id_hash IS NOT NULL").bind(now, userId),
    db.prepare("DELETE FROM rate_events WHERE user_id = ?").bind(userId),
    db.prepare("DELETE FROM active_streams WHERE user_id = ?").bind(userId),
    ...(user.email ? [db.prepare("DELETE FROM email_codes WHERE email = ?").bind(user.email)] : []),
    db.prepare("DELETE FROM users WHERE id = ?").bind(userId),
  ]);
}
