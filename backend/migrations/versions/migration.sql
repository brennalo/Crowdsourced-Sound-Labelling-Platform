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

--third time migration , deleted review table and add label_changes
-- ============================================================
-- Migration: label_changes audit log, drop annotations /
--            suggestion_reviews / researcher_reviews
-- Run once against Neon PostgreSQL
-- ============================================================

-- 1. label_changes — unified audit log replacing suggestion_reviews,
--    researcher_reviews, and annotations.
CREATE TABLE IF NOT EXISTS label_changes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    segment_id          UUID NOT NULL REFERENCES segments(id),
    changed_by_user_id  UUID REFERENCES users(id),  -- nullable: no actor for system-driven changes
    change_source       TEXT NOT NULL CHECK (
        change_source IN (
            'contributor_reject',
            'consensus_flip',
            'researcher_correction',
            'researcher_confirm'
        )
    ),
    old_label           TEXT,
    new_label           TEXT,
    changed_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_label_changes_segment    ON label_changes (segment_id);
CREATE INDEX IF NOT EXISTS idx_label_changes_changed_at ON label_changes (changed_at);
CREATE INDEX IF NOT EXISTS idx_label_changes_source     ON label_changes (change_source);

-- 2. Backfill label_changes from researcher_reviews before dropping it.
--    old_label is unknown historically (researcher_reviews never recorded it),
--    so it's left NULL for these backfilled rows — only new_label is accurate.
INSERT INTO label_changes (segment_id, changed_by_user_id, change_source, old_label, new_label, changed_at)
SELECT
    segment_id,
    researcher_id,
    CASE WHEN action = 'corrected' THEN 'researcher_correction' ELSE 'researcher_confirm' END,
    NULL,
    corrected_label,
    reviewed_at
FROM researcher_reviews;

-- 3. Drop tables replaced by label_changes.
--    suggestion_reviews and annotations were already unused in application
--    code before this migration (confirmed via grep) — dropping is safe.
DROP TABLE IF EXISTS researcher_reviews;
DROP TABLE IF EXISTS suggestion_reviews;
DROP TABLE IF EXISTS annotations;

-- Verify
SELECT 'migration complete' AS status;
SELECT count(*) AS backfilled_label_changes FROM label_changes;