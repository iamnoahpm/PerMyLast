import { config } from "../config.ts";
import type { Deps, Env } from "./env.ts";
import { exchangeAuthorizationCode, revocationConfigured } from "./appleRevoke.ts";
import { AuthError, b64urlEncode, sha256Hex, signJwt, verifyIdToken, verifyJwt, type IdTokenClaims } from "./jwt.ts";

export type Provider = "apple" | "google";

const PROVIDERS = {
  apple: { jwksUrl: "https://appleid.apple.com/auth/keys", issuers: ["https://appleid.apple.com"], audience: (e: Env) => e.APPLE_CLIENT_ID },
  google: {
    jwksUrl: "https://www.googleapis.com/oauth2/v3/certs",
    issuers: ["https://accounts.google.com", "accounts.google.com"],
    audience: (e: Env) => e.GOOGLE_CLIENT_ID,
  },
} as const;

export interface Session {
  user_id: string;
  access_token: string;
  refresh_token: string;
  expires_in: number;
}

/** The signed-in user's id from `Authorization: Bearer <access token>`, or null. */
export async function authenticate(req: Request, env: Env, now: number): Promise<string | null> {
  const match = /^Bearer\s+(.+)$/i.exec(req.headers.get("authorization") ?? "");
  if (!match) return null;
  try {
    const claims = await verifyJwt(match[1].trim(), env.JWT_SECRET, now);
    if (typeof claims.sub !== "string") return null;
    // A token outlives its account for up to ACCESS_TOKEN_TTL_S; a deleted account must stop working at once.
    const exists = await env.DB.prepare("SELECT 1 FROM users WHERE id = ?").bind(claims.sub).first();
    return exists ? claims.sub : null;
  } catch {
    return null;
  }
}

export async function issueSession(env: Env, userId: string, now: number): Promise<Session> {
  const accessToken = await signJwt(
    { sub: userId, iss: "permylast", iat: Math.floor(now / 1000), exp: Math.floor(now / 1000) + config.ACCESS_TOKEN_TTL_S },
    env.JWT_SECRET,
  );
  const refresh = b64urlEncode(crypto.getRandomValues(new Uint8Array(32)));
  await env.DB
    .prepare("INSERT INTO refresh_tokens (token_hash, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)")
    .bind(await sha256Hex(refresh), userId, now + config.REFRESH_TOKEN_TTL_S * 1000, now)
    .run();
  return { user_id: userId, access_token: accessToken, refresh_token: refresh, expires_in: config.ACCESS_TOKEN_TTL_S };
}

async function findOrCreateUser(env: Env, provider: Provider, claims: IdTokenClaims, now: number): Promise<string> {
  const column = provider === "apple" ? "apple_sub" : "google_sub";
  const lookup = () => env.DB.prepare(`SELECT id FROM users WHERE ${column} = ?`).bind(claims.sub).first<{ id: string }>();
  const existing = await lookup();
  if (existing) return existing.id;

  // Same verified email on another sign-in method: one account.
  let email = claims.email_verified ? claims.email ?? null : null;
  if (email) {
    const byEmail = await env.DB.prepare("SELECT id FROM users WHERE email = ?").bind(email).first<{ id: string }>();
    if (byEmail) {
      await env.DB.prepare(`UPDATE users SET ${column} = ? WHERE id = ? AND ${column} IS NULL`).bind(claims.sub, byEmail.id).run();
      const linked = await env.DB.prepare(`SELECT id FROM users WHERE id = ? AND ${column} = ?`).bind(byEmail.id, claims.sub).first();
      if (linked) return byEmail.id;
      email = null; // that account already has a different login for this provider: new account, email stays with the old one
    }
  }

  const id = crypto.randomUUID();
  try {
    await env.DB.batch([
      env.DB.prepare(`INSERT INTO users (id, email, ${column}, created_at) VALUES (?, ?, ?, ?)`).bind(id, email, claims.sub, now),
      env.DB.prepare("INSERT INTO profiles (user_id, created_at) VALUES (?, ?)").bind(id, now),
    ]);
    return id;
  } catch (error) {
    // Two first sign-ins racing: the other request won, so use its account.
    const winner = await lookup();
    if (winner) return winner.id;
    throw error;
  }
}

/** Trades a Sign in with Apple / Google ID token for a session. Apple's `nonce` is the raw value the app hashed. */
export async function signInWithProvider(env: Env, deps: Deps, provider: Provider, idToken: string, nonce?: string, authorizationCode?: string, fullName?: string): Promise<Session> {
  const p = PROVIDERS[provider];
  const audiences = p.audience(env).split(",").map((s) => s.trim()).filter(Boolean);
  if (audiences.length === 0) throw new AuthError(`${provider} sign-in is not configured`);
  const now = deps.now();
  const claims = await verifyIdToken(idToken, { jwksUrl: p.jwksUrl, issuers: [...p.issuers], audiences, fetch: deps.fetch, now });
  if (claims.nonce !== undefined) {
    if (!nonce || (claims.nonce !== nonce && claims.nonce !== (await sha256Hex(nonce)))) throw new AuthError("nonce mismatch");
  }
  const userId = await findOrCreateUser(env, provider, claims, now);
  // Apple shares the name only on the first authorization, so keep it when it arrives and never overwrite one we have.
  const name = fullName?.trim().slice(0, 100);
  if (provider === "apple" && name) await env.DB.prepare("UPDATE users SET name = ? WHERE id = ? AND name IS NULL").bind(name, userId).run();
  if (provider === "apple" && authorizationCode && revocationConfigured(env)) {
    // Best effort: sign-in must not fail because Apple's token endpoint did.
    const refresh = await exchangeAuthorizationCode(env, deps, authorizationCode);
    if (refresh) await env.DB.prepare("UPDATE users SET apple_refresh_token = ? WHERE id = ?").bind(refresh, userId).run();
  }
  return issueSession(env, userId, now);
}

/** Rotates a refresh token. Reusing one that was already rotated revokes every session of that user. */
export async function refreshSession(env: Env, deps: Deps, refreshToken: string): Promise<Session> {
  const now = deps.now();
  const hash = await sha256Hex(refreshToken);
  const row = await env.DB
    .prepare("SELECT user_id, expires_at, revoked FROM refresh_tokens WHERE token_hash = ?")
    .bind(hash)
    .first<{ user_id: string; expires_at: number; revoked: number }>();
  if (!row) throw new AuthError("unknown refresh token");
  if (row.revoked) {
    await env.DB.prepare("UPDATE refresh_tokens SET revoked = 1 WHERE user_id = ?").bind(row.user_id).run();
    throw new AuthError("refresh token reused");
  }
  if (row.expires_at <= now) throw new AuthError("refresh token expired");
  const claimed = await env.DB.prepare("UPDATE refresh_tokens SET revoked = 1 WHERE token_hash = ? AND revoked = 0").bind(hash).run();
  if (claimed.meta.changes !== 1) throw new AuthError("refresh token reused");
  return issueSession(env, row.user_id, now);
}
