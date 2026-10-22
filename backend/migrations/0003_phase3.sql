-- Phase 3: email-code sign-in, rate limiting, concurrent-stream limit.

-- One pending sign-in code per address. Only a keyed hash of the code is stored.
CREATE TABLE email_codes (
  email TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  window_start INTEGER NOT NULL,
  sent_in_window INTEGER NOT NULL DEFAULT 1
);

-- Requests per user per minute (FR-B9).
CREATE TABLE rate_events (
  user_id TEXT NOT NULL,
  at INTEGER NOT NULL
);
CREATE INDEX rate_events_user_idx ON rate_events (user_id, at);

-- Streams in flight per user (FR-B9). Rows older than the upstream timeout are ignored.
CREATE TABLE active_streams (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  started_at INTEGER NOT NULL
);
CREATE INDEX active_streams_user_idx ON active_streams (user_id, started_at);
