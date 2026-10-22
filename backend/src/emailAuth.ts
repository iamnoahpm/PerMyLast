// Sign-in with an emailed one-time code (the email "magic link" of FR-A7, as a code so it works in a
// sandboxed menu bar app without a URL scheme). Never reveals whether an address has an account.
import { config } from "../config.ts";
import { issueSession, type Session } from "./auth.ts";
import type { Deps, Env } from "./env.ts";
import { AuthError, b64urlEncode } from "./jwt.ts";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const WINDOW_MS = 15 * 60_000;

export function normalizeEmail(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const email = raw.trim().toLowerCase();
  return email.length <= 254 && EMAIL_RE.test(email) ? email : null;
}

async function codeHash(env: Env, email: string, code: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env.JWT_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return b64urlEncode(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`code:${email}:${code}`)));
}

function randomCode(): string {
  // Rejection sampling keeps the six digits uniform.
  const limit = 4_294_000_000; // largest multiple of 1e6 below 2^32
  for (;;) {
    const n = crypto.getRandomValues(new Uint32Array(1))[0];
    if (n < limit) return String(n % 1_000_000).padStart(6, "0");
  }
}

/** Sends a code. Quietly does nothing past the per-address limit, so the response never leaks anything. */
export async function requestEmailCode(env: Env, deps: Deps, email: string): Promise<void> {
  const now = deps.now();
  const row = await env.DB.prepare("SELECT window_start, sent_in_window FROM email_codes WHERE email = ?")
    .bind(email).first<{ window_start: number; sent_in_window: number }>();
  const inWindow = row && now - row.window_start < WINDOW_MS;
  if (inWindow && row.sent_in_window >= config.EMAIL_CODES_PER_WINDOW) return;

  const code = randomCode();
  await env.DB.prepare(
    `INSERT INTO email_codes (email, code_hash, expires_at, attempts, window_start, sent_in_window) VALUES (?, ?, ?, 0, ?, 1)
     ON CONFLICT (email) DO UPDATE SET code_hash = excluded.code_hash, expires_at = excluded.expires_at, attempts = 0,
       window_start = CASE WHEN ? THEN window_start ELSE excluded.window_start END,
       sent_in_window = CASE WHEN ? THEN sent_in_window + 1 ELSE 1 END`,
  ).bind(email, await codeHash(env, email, code), now + config.EMAIL_CODE_TTL_S * 1000, now, inWindow ? 1 : 0, inWindow ? 1 : 0).run();

  await deps.sendEmail(env, email, "Your Per My Last sign-in code",
    `Your sign-in code is ${code}. It works for ${config.EMAIL_CODE_TTL_S / 60} minutes. If you didn't ask for it, ignore this email.`);
}

export async function verifyEmailCode(env: Env, deps: Deps, email: string, code: string): Promise<Session> {
  const now = deps.now();
  // Count the attempt first, in the same statement that checks the limit, so guesses cannot race past it.
  const claimed = await env.DB.prepare("UPDATE email_codes SET attempts = attempts + 1 WHERE email = ? AND attempts < ? AND expires_at > ?")
    .bind(email, config.EMAIL_CODE_MAX_ATTEMPTS, now).run();
  if (claimed.meta.changes !== 1) throw new AuthError("no valid code");

  const row = await env.DB.prepare("SELECT code_hash FROM email_codes WHERE email = ?").bind(email).first<{ code_hash: string }>();
  const given = await codeHash(env, email, code.trim());
  if (!row || row.code_hash.length !== given.length || !timingSafeEqual(row.code_hash, given)) throw new AuthError("wrong code");

  const used = await env.DB.prepare("DELETE FROM email_codes WHERE email = ? AND code_hash = ?").bind(email, row.code_hash).run();
  if (used.meta.changes !== 1) throw new AuthError("code already used");
  return issueSession(env, await findOrCreateByEmail(env, email, now), now);
}

function timingSafeEqual(a: string, b: string): boolean {
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function findOrCreateByEmail(env: Env, email: string, now: number): Promise<string> {
  const find = () => env.DB.prepare("SELECT id FROM users WHERE email = ?").bind(email).first<{ id: string }>();
  const existing = await find();
  if (existing) return existing.id;
  const id = crypto.randomUUID();
  try {
    await env.DB.batch([
      env.DB.prepare("INSERT INTO users (id, email, created_at) VALUES (?, ?, ?)").bind(id, email, now),
      env.DB.prepare("INSERT INTO profiles (user_id, created_at) VALUES (?, ?)").bind(id, now),
    ]);
    return id;
  } catch (error) {
    const winner = await find();
    if (winner) return winner.id;
    throw error;
  }
}
