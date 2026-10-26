// DELETE /v1/account: erases the signed-in account and everything stored about it (App Store guideline 5.1.1(v)).
// If Sign in with Apple is set up for revocation, the user's Apple token is revoked first. Foreign keys cascade to
// sessions, profile, entitlements, usage periods and usage events. What is left is not linked to the person: the Apple/Google subject goes with the user row, and the install-id hash is kept in `deleted_installs`
// only so that deleting and re-creating an account cannot be used to claim the Free credits again on the same Mac.
import type { Deps, Env } from "./env.ts";
import { revocationConfigured, revokeAppleToken } from "./appleRevoke.ts";

export async function deleteAccount(env: Env, deps: Deps, userId: string): Promise<void> {
  const db = env.DB, now = deps.now();
  const user = await db.prepare("SELECT email, apple_refresh_token FROM users WHERE id = ?").bind(userId).first<{ email: string | null; apple_refresh_token: string | null }>();
  if (!user) return;
  // Revoke first, but never let Apple being slow or down block someone's right to delete their account.
  if (user.apple_refresh_token && revocationConfigured(env)) await revokeAppleToken(env, deps, user.apple_refresh_token);
  await db.batch([
    db.prepare("INSERT OR IGNORE INTO deleted_installs (install_id_hash, deleted_at) SELECT install_id_hash, ? FROM profiles WHERE user_id = ? AND install_id_hash IS NOT NULL").bind(now, userId),
    db.prepare("DELETE FROM rate_events WHERE user_id = ?").bind(userId),
    db.prepare("DELETE FROM active_streams WHERE user_id = ?").bind(userId),
    ...(user.email ? [db.prepare("DELETE FROM email_codes WHERE email = ?").bind(user.email)] : []),
    db.prepare("DELETE FROM users WHERE id = ?").bind(userId),
  ]);
}
