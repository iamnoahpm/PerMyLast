-- Data model (PRD section 6) for Cloudflare D1 (SQLite). Times are epoch milliseconds (UTC).
-- There is no row-level security: clients never reach D1. Only the Worker does, and it scopes every
-- query to the user id inside a verified session token.

-- Accounts. Replaces the auth provider's user table (Cloudflare has none).
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  email TEXT,
  apple_sub TEXT,
  google_sub TEXT,
  created_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX users_email_key ON users (email) WHERE email IS NOT NULL;
CREATE UNIQUE INDEX users_apple_sub_key ON users (apple_sub) WHERE apple_sub IS NOT NULL;
CREATE UNIQUE INDEX users_google_sub_key ON users (google_sub) WHERE google_sub IS NOT NULL;

-- Only a hash of the refresh token is stored.
CREATE TABLE refresh_tokens (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  revoked INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX refresh_tokens_user_idx ON refresh_tokens (user_id);

CREATE TABLE profiles (
  user_id TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  install_id_hash TEXT,
  created_at INTEGER NOT NULL
);
-- One trial per install: a second account on the same Mac cannot claim the hash again.
CREATE UNIQUE INDEX profiles_install_id_hash_key ON profiles (install_id_hash) WHERE install_id_hash IS NOT NULL;

CREATE TABLE entitlements (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  plan TEXT NOT NULL CHECK (plan IN ('trial', 'lifetime', 'pro_monthly', 'pro_yearly')),
  status TEXT NOT NULL CHECK (status IN ('active', 'expired', 'refunded')),
  starts_at INTEGER NOT NULL,
  expires_at INTEGER,
  updates_until INTEGER,
  source TEXT NOT NULL CHECK (source IN ('storekit', 'lemonsqueezy', 'manual')),
  external_id TEXT,
  updated_at INTEGER NOT NULL
);
CREATE INDEX entitlements_user_idx ON entitlements (user_id);
-- Webhooks upsert by (source, external_id).
CREATE UNIQUE INDEX entitlements_external_key ON entitlements (source, external_id) WHERE external_id IS NOT NULL;
-- One trial per user.
CREATE UNIQUE INDEX entitlements_one_trial_key ON entitlements (user_id) WHERE plan = 'trial';

CREATE TABLE usage_periods (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('trial', 'pro')),
  period_start INTEGER NOT NULL,
  period_end INTEGER NOT NULL,
  allowance INTEGER NOT NULL CHECK (allowance >= 0),
  used INTEGER NOT NULL DEFAULT 0,
  UNIQUE (user_id, kind, period_start),
  CHECK (used >= 0 AND used <= allowance)
);

CREATE TABLE run_reservations (
  id TEXT PRIMARY KEY,
  usage_period_id TEXT NOT NULL REFERENCES usage_periods (id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'reserved' CHECK (status IN ('reserved', 'committed', 'refunded')),
  created_at INTEGER NOT NULL
);
CREATE INDEX run_reservations_period_idx ON run_reservations (usage_period_id);

-- Token counts and status only; never prompt or output text (NFR-4).
CREATE TABLE usage_events (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  template_id TEXT NOT NULL,
  model TEXT,
  input_tokens INTEGER,
  output_tokens INTEGER,
  cache_read_tokens INTEGER,
  cache_write_tokens INTEGER,
  latency_ms INTEGER,
  status TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX usage_events_user_idx ON usage_events (user_id, created_at);

CREATE TABLE templates (
  id TEXT NOT NULL,
  version INTEGER NOT NULL,
  json TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (id, version)
);
CREATE UNIQUE INDEX templates_one_active_key ON templates (id) WHERE active = 1;
