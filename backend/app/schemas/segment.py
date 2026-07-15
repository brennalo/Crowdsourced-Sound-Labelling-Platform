from pydantic import BaseModel
from datetime import datetime
from typing import Literal
import uuid


class SegmentOut(BaseModel):
    id: uuid.UUID
    recording_id: uuid.UUID
    user_id: uuid.UUID
    gcs_path: str
    start_sec: float
    end_sec: float
    review_status: str
    effective_label: str | None
    model_label: str | None
    model_confidence: float | None
    pool_entry_reason: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


# ── My Clips (contributor's own segments) ─────────────────────

class MySegmentOut(SegmentOut):
    """SegmentOut with recording metadata for flat-list view."""
    recording_recorded_at: datetime | None = None


# ── Suggestion review (high-confidence, contributor own segment) ──

class SuggestionReviewCreate(BaseModel):
    # accepted → effective_label = model_label
    # rejected → must supply corrected_label
    decision: Literal["accepted", "rejected"]
    corrected_label: str | None = None  # required when decision == "rejected"


# ── Manual label (low-confidence, contributor own segment) ────

class ManualLabelCreate(BaseModel):
    label: str   # any active label name, or "other"


# ── Consensus ────────────────────────────────────────────────

class ConsensusSegmentOut(SegmentOut):
    agree_count: int
    disagree_count: int
    consensus_required: int
    user_voted: bool  # has the calling user already voted


class ConsensusVoteCreate(BaseModel):
    verdict: Literal["agree", "disagree"]


class ConsensusVoteOut(BaseModel):
    id: uuid.UUID
    segment_id: uuid.UUID
    verdict: str
    voted_at: datetime
    consensus_reached: bool
    # set when consensus_reached is True; the final effective_label
    final_label: str | None

    model_config = {"from_attributes": True}


# ── Training pool ─────────────────────────────────────────────

class TrainingPoolSegmentOut(SegmentOut):
    """Segment in the training pool — all users' segments."""
    uploader_display_name: str | None = None
    agree_count: int = 0
    disagree_count: int = 0
    consensus_open: bool = False


# ── Researcher review ─────────────────────────────────────────

class ResearcherReviewCreate(BaseModel):
    action: Literal["confirmed", "corrected"]
    corrected_label: str | None = None  # required when action == "corrected"


# Response for POST /researcher/review/{id} is now LabelChangeOut
# (see app.schemas.label_change) — the review is recorded as a label_changes row.


# ── Export stats ──────────────────────────────────────────────

class ExportStatsOut(BaseModel):
    total_in_pool: int
    label_distribution: dict[str, int]
    consensus_flips: int
    researcher_corrections: int
    added_last_7_days: int