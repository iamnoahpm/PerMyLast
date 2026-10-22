import { env } from "cloudflare:test";
import type { Env } from "../src/env.ts";

export const testEnv = env as unknown as Env;
export const HOUR = 3_600_000;
export const DAY = 24 * HOUR;

export async function newUser(): Promise<string> {
  const id = crypto.randomUUID();
  await testEnv.DB.batch([
    testEnv.DB.prepare("INSERT INTO users (id, email, created_at) VALUES (?, ?, ?)").bind(id, `${id}@test`, Date.now()),
    testEnv.DB.prepare("INSERT INTO profiles (user_id, created_at) VALUES (?, ?)").bind(id, Date.now()),
  ]);
  return id;
}

export async function grant(
  userId: string,
  plan: string,
  o: { status?: string; starts?: number; expires?: number | null; updates?: number | null } = {},
): Promise<void> {
  await testEnv.DB
    .prepare("INSERT INTO entitlements (id, user_id, plan, status, starts_at, expires_at, updates_until, source, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, 'manual', ?)")
    .bind(crypto.randomUUID(), userId, plan, o.status ?? "active", o.starts ?? Date.now() - HOUR, o.expires ?? null, o.updates ?? null, Date.now())
    .run();
}

export async function usage(userId: string): Promise<{ used: number; allowance: number } | null> {
  return testEnv.DB.prepare("SELECT used, allowance FROM usage_periods WHERE user_id = ?").bind(userId).first();
}
