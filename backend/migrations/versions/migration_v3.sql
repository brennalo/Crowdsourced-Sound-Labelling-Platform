-- ============================================================
-- Migration: thresholds config, device tokens (FCM), soft-delete
--            users, segment sequence numbers
-- Run once against Neon PostgreSQL
-- ============================================================

-- 1. system_config — single-row table for researcher-adjustable thresholds
--    (silence threshold, suggestion confidence threshold, retrain rejection
--    count). id is pinned to 1 via CHECK, so there's only ever one row.
CREATE TABLE IF NOT EXISTS system_config (
    id                     INTEGER PRIMARY KEY CHECK (id = 1),
    silence_threshold_dbfs FLOAT NOT NULL DEFAULT -40.0,
    confidence_threshold   FLOAT NOT NULL DEFAULT 0.75,
    rejection_threshold    INTEGER NOT NULL DEFAULT 150,
    updated_by             UUID REFERENCES users(id),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed the singleton row with defaults matching what was previously
-- hardcoded in backend/.env / segmentation.py.
INSERT INTO system_config (id, silence_threshold_dbfs, confidence_threshold, rejection_threshold)
VALUES (1, -40.0, 0.75, 150)
ON CONFLICT (id) DO NOTHING;

-- 2. device_tokens — FCM registration tokens, used to push segmentation /
--    export / consensus-resolution completion instead of polling.
CREATE TABLE IF NOT EXISTS device_tokens (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users(id),
    token         TEXT NOT NULL,
    platform      TEXT,  -- android | ios
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_device_tokens_token UNIQUE (token)
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_user_id ON device_tokens (user_id);

-- 3. Soft delete for users — admin "delete" deactivates rather than
--    cascading into a user's recordings/segments/votes.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS is_active      BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS deactivated_at TIMESTAMPTZ;

-- 4. Segment identifier — human-friendly "Segment N/Total" display,
--    replacing raw start_sec/end_sec in flat-list views.
ALTER TABLE segments
  ADD COLUMN IF NOT EXISTS sequence_num INTEGER;

ALTER TABLE recordings
  ADD COLUMN IF NOT EXISTS total_segments INTEGER;

-- 5. Backfill sequence_num / total_segments for segments that already
--    exist, so old recordings get sensible display labels too — not just
--    ones segmented after this migration. Numbers non-silent segments in
--    upload order per recording, matching what the app will assign to new
--    segments going forward.
WITH numbered AS (
    SELECT
        id,
        recording_id,
        ROW_NUMBER() OVER (
            PARTITION BY recording_id
            ORDER BY created_at ASC
        ) AS rn
    FROM segments
    WHERE is_silent = FALSE
)
UPDATE segments s
SET sequence_num = numbered.rn
FROM numbered
WHERE s.id = numbered.id
  AND s.sequence_num IS NULL;

WITH totals AS (
    SELECT recording_id, count(*) AS n
    FROM segments
    WHERE is_silent = FALSE
    GROUP BY recording_id
)
UPDATE recordings r
SET total_segments = totals.n
FROM totals
WHERE r.id = totals.recording_id
  AND r.total_segments IS NULL;

-- Verify
SELECT 'migration complete' AS status;
SELECT count(*) AS system_config_rows FROM system_config;
SELECT count(*) AS segments_missing_sequence_num FROM segments WHERE is_silent = FALSE AND sequence_num IS NULL;
