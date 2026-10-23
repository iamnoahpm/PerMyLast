-- Onboarding funnel events. Anonymous: install_id is a SHA-256 of a random per-install id, never an email or user id,
-- so events can be logged before anyone signs in. No text the user typed or selected is ever stored.
CREATE TABLE onboarding_events (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  install_id  TEXT NOT NULL,
  name        TEXT NOT NULL,
  at          INTEGER NOT NULL,
  app_version TEXT,
  props       TEXT
);
CREATE INDEX onboarding_events_name_idx ON onboarding_events (name, at);
CREATE INDEX onboarding_events_install_idx ON onboarding_events (install_id, at);
