-- Phase 5: a run on a larger model costs more than one run (NFR-6). The reservation remembers its weight so a refund gives back exactly that many.
ALTER TABLE run_reservations ADD COLUMN weight INTEGER NOT NULL DEFAULT 1 CHECK (weight >= 1);
