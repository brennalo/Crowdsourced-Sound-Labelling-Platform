"""initial schema

Revision ID: 001
Revises:
Create Date: 2024-01-01 00:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision: str = "001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("email", sa.String(), nullable=False, unique=True),
        sa.Column("password_hash", sa.String(), nullable=False),
        sa.Column("display_name", sa.String(), nullable=True),
        sa.Column("role", sa.String(), nullable=False, server_default="contributor"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "recordings",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("gcs_raw_path", sa.String(), nullable=False),
        sa.Column("duration_sec", sa.Float(), nullable=True),
        sa.Column("recorded_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("location_lat", sa.Float(), nullable=True),
        sa.Column("location_lng", sa.Float(), nullable=True),
        sa.Column("status", sa.String(), nullable=False, server_default="processing"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_recordings_user_id", "recordings", ["user_id"])

    op.create_table(
        "segments",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("recording_id", UUID(as_uuid=True), sa.ForeignKey("recordings.id"), nullable=False),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("gcs_path", sa.String(), nullable=False),
        sa.Column("start_sec", sa.Float(), nullable=False),
        sa.Column("end_sec", sa.Float(), nullable=False),
        sa.Column("is_silent", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("review_status", sa.String(), nullable=False, server_default="pending"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_segments_recording_id", "segments", ["recording_id"])
    op.create_index("ix_segments_user_id", "segments", ["user_id"])
    op.create_index("ix_segments_review_status", "segments", ["review_status"])

    op.create_table(
        "annotations",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("segment_id", UUID(as_uuid=True), sa.ForeignKey("segments.id"), nullable=False),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("label", sa.String(), nullable=False),
        sa.Column("source", sa.String(), nullable=False),
        sa.Column("confidence", sa.Float(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_annotations_segment_id", "annotations", ["segment_id"])
    op.create_index("ix_annotations_source", "annotations", ["source"])

    op.create_table(
        "model_versions",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("version_tag", sa.String(), nullable=False),
        sa.Column("gcs_model_path", sa.String(), nullable=False),
        sa.Column("trigger_reason", sa.String(), nullable=False),
        sa.Column("training_samples", sa.Integer(), nullable=True),
        sa.Column("accuracy", sa.Float(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "suggestion_reviews",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("segment_id", UUID(as_uuid=True), sa.ForeignKey("segments.id"), nullable=False),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("annotation_id", UUID(as_uuid=True), sa.ForeignKey("annotations.id"), nullable=False),
        sa.Column("decision", sa.String(), nullable=False),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_suggestion_reviews_decision", "suggestion_reviews", ["decision"])

    op.create_table(
        "retraining_jobs",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("triggered_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("triggered_by", sa.String(), nullable=False),
        sa.Column("status", sa.String(), nullable=False, server_default="queued"),
        sa.Column("rejection_count", sa.Integer(), nullable=True),
        sa.Column("model_version_id", UUID(as_uuid=True), sa.ForeignKey("model_versions.id"), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("error_log", sa.Text(), nullable=True),
    )

    op.create_table(
        "export_jobs",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("requested_by", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("status", sa.String(), nullable=False, server_default="queued"),
        sa.Column("gcs_export_path", sa.String(), nullable=True),
        sa.Column("requested_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_table("export_jobs")
    op.drop_table("retraining_jobs")
    op.drop_table("suggestion_reviews")
    op.drop_table("model_versions")
    op.drop_table("annotations")
    op.drop_table("segments")
    op.drop_table("recordings")
    op.drop_table("users")
