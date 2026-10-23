-- Pricing change: the one-time trial (21 days, 50 credits) becomes a Free plan that renews 21 credits every month,
-- and the flat lifetime renewal becomes a discounted-upgrade ladder.

-- Free needs no entitlement row: every account that has claimed its Mac gets it. Legacy trial rows are dropped, and
-- everyone starts with a full month of Free credits.
DELETE FROM entitlements WHERE plan = 'trial';

-- Upgrades a Power user (lifetime) account has bought. Upgrade n costs 50% of the previous price, so the next product
-- offered is tier MIN(upgrade_count + 1, UPGRADE_TIERS).
ALTER TABLE entitlements ADD COLUMN upgrade_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE pending_licenses ADD COLUMN tier INTEGER NOT NULL DEFAULT 1;

-- usage_periods.kind: 'trial' becomes 'free'. SQLite cannot alter a CHECK, so rebuild both tables, keeping Pro usage.
CREATE TABLE usage_periods_new (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('free', 'pro')),
  period_start INTEGER NOT NULL,
  period_end INTEGER NOT NULL,
  allowance INTEGER NOT NULL CHECK (allowance >= 0),
  used INTEGER NOT NULL DEFAULT 0,
  UNIQUE (user_id, kind, period_start),
  CHECK (used >= 0 AND used <= allowance)
);
CREATE TABLE run_reservations_new (
  id TEXT PRIMARY KEY,
  usage_period_id TEXT NOT NULL REFERENCES usage_periods_new (id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'reserved' CHECK (status IN ('reserved', 'committed', 'refunded')),
  created_at INTEGER NOT NULL,
  weight INTEGER NOT NULL DEFAULT 1 CHECK (weight >= 1)
);
INSERT INTO usage_periods_new SELECT * FROM usage_periods WHERE kind = 'pro';
INSERT INTO run_reservations_new SELECT r.id, r.usage_period_id, r.status, r.created_at, r.weight
  FROM run_reservations r JOIN usage_periods_new u ON u.id = r.usage_period_id;
DROP TABLE run_reservations;
DROP TABLE usage_periods;
ALTER TABLE usage_periods_new RENAME TO usage_periods;
ALTER TABLE run_reservations_new RENAME TO run_reservations;
CREATE INDEX run_reservations_period_idx ON run_reservations (usage_period_id);
