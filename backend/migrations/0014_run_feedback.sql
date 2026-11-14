-- Ratings of a finished run ("Bad / Fine / Good"), anonymous: install_id is a SHA-256 of a random per-install id, never an
-- email or user id. The rating row holds only settings (model, effort, mode...). The text columns stay NULL unless the person
-- said yes, after seeing exactly what would be sent, to sharing that run (shared = 1).
CREATE TABLE run_feedback (
  id           TEXT PRIMARY KEY,          -- made by the app, so the later "share this run" call updates the same row
  install_id   TEXT NOT NULL,
  created_at   INTEGER NOT NULL,
  shared_at    INTEGER,
  rating       TEXT NOT NULL CHECK (rating IN ('bad', 'fine', 'good')),
  app_version  TEXT,
  os_version   TEXT,
  app_language TEXT,
  model        TEXT,
  effort       TEXT,
  mode         TEXT,
  preset       TEXT,
  via          TEXT,                      -- 'proxy' (our key) or 'own_key'
  image_count  INTEGER,
  shared       INTEGER NOT NULL DEFAULT 0,
  prompt       TEXT,
  input_text   TEXT,
  output_text  TEXT
);
CREATE INDEX run_feedback_install_idx ON run_feedback (install_id, created_at);
CREATE INDEX run_feedback_rating_idx ON run_feedback (rating, created_at);
