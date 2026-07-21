# Programmer Name : Brenna Lo
# Program Name : consensus.py
# Description : Consensus API endpoints for managing label disputes
# First Written on : 2024-06-10
# Edited on : 2024-07-18

"""
Consensus — any authenticated user can report a training_pool segment as
wrong, proposing what they think the correct label should be. A report opens
a consensus_open vote on that specific proposal. First side to 3 votes wins.
agree = accept the proposed_label → effective_label becomes proposed_label
disagree = reject the proposal → effective_label stays as it was
Odd quorum (3) means ties are structurally impossible.
"""
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.database import get_db
from app.models.user import User
from app.models.segment import Segment
from app.models.recording import Recording
from app.models.consensus_vote import ConsensusVote
from app.models.label import Label
from app.schemas.segment import (
    ConsensusSegmentOut, ConsensusReportCreate, ConsensusVoteCreate, ConsensusVoteOut,
)
from app.auth import get_current_user
from app.services.label_change import record_label_change
import uuid

router = APIRouter(prefix="/consensus", tags=["consensus"])

CONSENSUS_REQUIRED = 3


@router.get("/open", response_model=list[ConsensusSegmentOut])
async def list_open_consensus(
    limit: int = Query(50, le=100),
    offset: int = Query(0),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """All currently open consensus votes with current tallies."""
    result = await db.execute(
        select(
            Segment,
            User.display_name.label("uploader_name"),
            Recording.recorded_at.label("recording_recorded_at"),
            Recording.total_segments.label("recording_total_segments"),
        )
        .join(User, User.id == Segment.user_id)
        .outerjoin(Recording, Recording.id == Segment.recording_id)
        .where(Segment.review_status == "consensus_open", Segment.is_silent == False)
        .order_by(Segment.created_at.asc())
        .offset(offset)
        .limit(limit)
    )
    rows = result.all()
    segments = [row[0] for row in rows]
    context_by_id = {
        row[0].id: {
            "uploader_display_name": row[1],
            "recording_recorded_at": row[2],
            "recording_total_segments": row[3],
        }
        for row in rows
    }

    # Batch fetch vote counts
    seg_ids = [s.id for s in segments]
    votes_result = await db.execute(
        select(ConsensusVote.segment_id, ConsensusVote.verdict, func.count().label("n"))
        .where(ConsensusVote.segment_id.in_(seg_ids))
        .group_by(ConsensusVote.segment_id, ConsensusVote.verdict)
    )
    counts: dict[uuid.UUID, dict[str, int]] = {}
    for seg_id, verdict, n in votes_result:
        counts.setdefault(seg_id, {})[verdict] = n

    # Which segments has the caller voted on
    voted_result = await db.execute(
        select(ConsensusVote.segment_id)
        .where(
            ConsensusVote.segment_id.in_(seg_ids),
            ConsensusVote.voter_id == current_user.id,
        )
    )
    voted_set = {row[0] for row in voted_result}

    output = []
    for seg in segments:
        c = counts.get(seg.id, {})
        ctx = context_by_id.get(seg.id, {})
        output.append(ConsensusSegmentOut(
            **SegmentOut_from(seg),
            agree_count=c.get("agree", 0),
            disagree_count=c.get("disagree", 0),
            consensus_required=CONSENSUS_REQUIRED,
            user_voted=seg.id in voted_set,
            proposed_label=seg.proposed_label,
            uploader_display_name=ctx.get("uploader_display_name"),
            recording_recorded_at=ctx.get("recording_recorded_at"),
            recording_total_segments=ctx.get("recording_total_segments"),
        ))
    return output


def SegmentOut_from(seg: Segment) -> dict:
    from app.schemas.segment import SegmentOut
    return SegmentOut.model_validate(seg).model_dump()


@router.post("/report/{segment_id}", status_code=status.HTTP_200_OK)
async def report_segment(
    segment_id: uuid.UUID,
    body: ConsensusReportCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Report a training_pool segment as incorrectly labelled, proposing what
    it should be instead. Opens consensus voting on that specific proposal.
    Reporter's vote is NOT auto-cast — they must then call /vote to cast
    agree (in favor of their own proposal) or disagree.
    """
    result = await db.execute(select(Segment).where(Segment.id == segment_id))
    segment = result.scalar_one_or_none()
    if not segment:
        raise HTTPException(status_code=404, detail="Segment not found")
    if segment.review_status == "consensus_open":
        return {"detail": "Already open for consensus"}
    if segment.review_status != "training_pool":
        raise HTTPException(status_code=409, detail="Only training_pool segments can be reported")

    label_result = await db.execute(
        select(Label).where(Label.name == body.proposed_label, Label.is_active == True)
    )
    if not label_result.scalar_one_or_none():
        raise HTTPException(status_code=422, detail="proposed_label is not a known active label")
    if body.proposed_label == segment.effective_label:
        raise HTTPException(status_code=422, detail="Proposed label matches the current label")

    segment.review_status = "consensus_open"
    segment.proposed_label = body.proposed_label
    await db.commit()
    return {"detail": "Consensus voting opened", "segment_id": str(segment_id), "proposed_label": body.proposed_label}


@router.post("/vote/{segment_id}", response_model=ConsensusVoteOut, status_code=status.HTTP_201_CREATED)
async def cast_vote(
    segment_id: uuid.UUID,
    body: ConsensusVoteCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(Segment).where(Segment.id == segment_id))
    segment = result.scalar_one_or_none()
    if not segment:
        raise HTTPException(status_code=404, detail="Segment not found")
    if segment.review_status != "consensus_open":
        raise HTTPException(status_code=409, detail="Segment is not open for consensus voting")

    # Prevent double vote
    existing = await db.execute(
        select(ConsensusVote).where(
            ConsensusVote.segment_id == segment_id,
            ConsensusVote.voter_id == current_user.id,
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Already voted on this segment")

    vote = ConsensusVote(
        id=uuid.uuid4(),
        segment_id=segment_id,
        voter_id=current_user.id,
        verdict=body.verdict,
    )
    db.add(vote)
    await db.flush()

    # Recount
    counts_result = await db.execute(
        select(ConsensusVote.verdict, func.count().label("n"))
        .where(ConsensusVote.segment_id == segment_id)
        .group_by(ConsensusVote.verdict)
    )
    counts = {row.verdict: row.n for row in counts_result}
    agree_n = counts.get("agree", 0)
    disagree_n = counts.get("disagree", 0)

    consensus_reached = False
    final_label = None

    if agree_n >= CONSENSUS_REQUIRED:
        # Proposal accepted — effective_label becomes what was proposed
        old_label = segment.effective_label
        new_label = segment.proposed_label
        segment.effective_label = new_label
        segment.review_status = "training_pool"
        segment.proposed_label = None
        consensus_reached = True
        final_label = new_label
        await record_label_change(
            db,
            segment_id=segment.id,
            change_source="consensus_flip",
            old_label=old_label,
            new_label=new_label,
            changed_by_user_id=current_user.id,
        )
    elif disagree_n >= CONSENSUS_REQUIRED:
        # Proposal rejected — effective_label stays as it was
        segment.review_status = "training_pool"
        segment.proposed_label = None
        consensus_reached = True
        final_label = segment.effective_label

    # Capture voter ids for the resolution push BEFORE we clear the round's
    # votes below — otherwise this set would come back empty.
    notify_ids: set[uuid.UUID] = set()
    if consensus_reached:
        voter_ids_result = await db.execute(
            select(ConsensusVote.voter_id).where(ConsensusVote.segment_id == segment_id).distinct()
        )
        notify_ids = {row[0] for row in voter_ids_result}
        notify_ids.add(segment.user_id)  # the contributor who recorded it

        # Clear this round's votes — they're scoped to the resolved proposal,
        # not to the segment forever. Without this, if the segment gets
        # reported again later with a new proposed_label, the same voters
        # would be blocked by UNIQUE(segment_id, voter_id) from voting on
        # what is, in effect, a brand new dispute.
        await db.execute(
            ConsensusVote.__table__.delete().where(ConsensusVote.segment_id == segment_id)
        )

    # Capture the just-cast vote's fields before commit expires/deletes it —
    # avoids re-reading a row that may no longer exist once cleared above.
    vote_id, vote_verdict, vote_voted_at = vote.id, vote.verdict, vote.voted_at

    await db.commit()

    if consensus_reached:
        from app.services.push import send_push_to_users
        await send_push_to_users(
            db,
            user_ids=list(notify_ids),
            data={"type": "consensus_resolved", "segment_id": str(segment_id)},
            notification={
                "title": "Consensus reached",
                "body": (
                    f'Label set to "{final_label}"' if final_label else "A disputed segment was resolved."
                ),
            },
        )

    return ConsensusVoteOut(
        id=vote_id,
        segment_id=segment_id,
        verdict=vote_verdict,
        voted_at=vote_voted_at,
        consensus_reached=consensus_reached,
        final_label=final_label,
    )