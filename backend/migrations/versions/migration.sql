-- ============================================================
-- Migration: full redesign
-- Run once against Neon PostgreSQL
-- ============================================================

-- 1. Add new columns to segments
ALTER TABLE segments
  ADD COLUMN IF NOT EXISTS effective_label    TEXT,
  ADD COLUMN IF NOT EXISTS model_label        TEXT,
  ADD COLUMN IF NOT EXISTS model_confidence   FLOAT,
  ADD COLUMN IF NOT EXISTS pool_entry_reason  TEXT;  -- manual | accepted | auto_7day

-- review_status values (TEXT, no enum constraint):
--   annotation_pending  low-confidence, contributor must pick label
--   suggestion_pending  high-confidence, contributor accepts/rejects
--   excluded_other      labelled "other", out of pool but re-labelable
--   training_pool       in the training pool
--   consensus_open      disputed, votes in progress

-- 2. labels table — dynamic label list fetched by Flutter
CREATE TABLE IF NOT EXISTS labels (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name         TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    is_active    BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO labels (name, display_name) VALUES
  ('environment', 'Environment'),
  ('chainsaw',    'Chainsaw')
ON CONFLICT (name) DO NOTHING;

-- 3. consensus_votes — replaces suggestion_reviews & old consensus_reviews
CREATE TABLE IF NOT EXISTS consensus_votes (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    segment_id  UUID NOT NULL REFERENCES segments(id),
    voter_id    UUID NOT NULL REFERENCES users(id),
    verdict     TEXT NOT NULL CHECK (verdict IN ('agree', 'disagree')),
    voted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (segment_id, voter_id)
);

CREATE INDEX IF NOT EXISTS idx_consensus_votes_segment ON consensus_votes (segment_id);

-- 4. researcher_reviews
CREATE TABLE IF NOT EXISTS researcher_reviews (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    segment_id       UUID NOT NULL REFERENCES segments(id),
    researcher_id    UUID NOT NULL REFERENCES users(id),
    action           TEXT NOT NULL CHECK (action IN ('confirmed', 'corrected')),
    corrected_label  TEXT,
    reviewed_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_researcher_reviews_segment ON researcher_reviews (segment_id);

-- 5. Update users role to allow 'researcher'
-- role column is already TEXT, no constraint change needed.

-- 6. Backfill: existing 'pending' segments → review_status will be set by
--    the next inference pass. For now mark them annotation_pending so they
--    surface in My Clips.
UPDATE segments
SET review_status = 'annotation_pending'
WHERE review_status = 'pending' AND is_silent = FALSE;

-- Verify
SELECT 'migration complete' AS status;
