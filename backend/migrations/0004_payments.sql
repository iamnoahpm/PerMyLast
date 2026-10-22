-- Phase 4: payments. Lemon Squeezy (direct sales) and the Mac App Store both write to `entitlements`.

-- The provider's own timestamp for the last change we applied, so an older event replayed late cannot undo a newer one.
ALTER TABLE entitlements ADD COLUMN source_updated_at INTEGER;

-- Webhook deliveries already handled, by a hash of the exact body (retries are identical) or the provider's own id.
CREATE TABLE webhook_events (
  event_key TEXT PRIMARY KEY,
  source TEXT NOT NULL,
  received_at INTEGER NOT NULL
);

-- One-off purchases applied once (renewals add 12 months each; they must never apply twice).
CREATE TABLE applied_purchases (
  source TEXT NOT NULL,
  external_id TEXT NOT NULL,
  applied_at INTEGER NOT NULL,
  PRIMARY KEY (source, external_id)
);

-- Lifetime purchases made before signing in (no account id came with the order). Claimed with the licence key.
CREATE TABLE pending_licenses (
  order_id TEXT PRIMARY KEY,
  source TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('lifetime', 'lifetime_renewal')),
  email TEXT,
  purchased_at INTEGER NOT NULL,
  claimed_by TEXT REFERENCES users (id) ON DELETE SET NULL,
  created_at INTEGER NOT NULL
);

-- Only a hash of each licence key is stored.
CREATE TABLE license_keys (
  key_hash TEXT PRIMARY KEY,
  order_id TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX license_keys_order_idx ON license_keys (order_id);
