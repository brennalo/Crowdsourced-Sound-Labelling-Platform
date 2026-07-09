"""
Consensus — any authenticated user can report a training_pool segment as wrong.
A report opens a consensus_open vote. First side to 3 votes wins.
agree = current effective_label is correct → stays in pool unchanged
disagree = current effective_label is wrong → label flipped, stays in pool
Odd quorum (3) means ties are structurally impossible.
"""
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.database import get_db
from app.models.user import User
from app.models.segment import Segment
from app.models.consensus_vote import ConsensusVote
from app.schemas.segment import ConsensusSegmentOut, ConsensusVoteCreate, ConsensusVoteOut
from app.auth import get_current_user
import uuid

router = APIRouter(prefix="/consensus", tags=["consensus"])

CONSENSUS_REQUIRED = 3
OPPOSITE = {"chainsaw": "environment", "environment": "chainsaw"}


@router.get("/open", response_model=list[ConsensusSegmentOut])
async def list_open_consensus(
    limit: int = Query(50, le=100),
    offset: int = Query(0),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """All currently open consensus votes with current tallies."""
    result = await db.execute(
        select(Segment)
        .where(Segment.review_status == "consensus_open", Segment.is_silent == False)
        .order_by(Segment.created_at.asc())
        .offset(offset)
        .limit(limit)
    )
    segments = result.scalars().all()

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
        output.append(ConsensusSegmentOut(
            **SegmentOut_from(seg),
            agree_count=c.get("agree", 0),
            disagree_count=c.get("disagree", 0),
            consensus_required=CONSENSUS_REQUIRED,
            user_voted=seg.id in voted_set,
        ))
    return output


def SegmentOut_from(seg: Segment) -> dict:
    from app.schemas.segment import SegmentOut
    return SegmentOut.model_validate(seg).model_dump()


@router.post("/report/{segment_id}", status_code=status.HTTP_200_OK)
async def report_segment(
    segment_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Report a training_pool segment as incorrectly labelled.
    Opens consensus voting. Reporter's vote is NOT auto-cast —
    they must then call /vote to cast disagree.
    """
    result = await db.execute(select(Segment).where(Segment.id == segment_id))
    segment = result.scalar_one_or_none()
    if not segment:
        raise HTTPException(status_code=404, detail="Segment not found")
    if segment.review_status == "consensus_open":
        return {"detail": "Already open for consensus"}
    if segment.review_status != "training_pool":
        raise HTTPException(status_code=409, detail="Only training_pool segments can be reported")

    segment.review_status = "consensus_open"
    await db.commit()
    return {"detail": "Consensus voting opened", "segment_id": str(segment_id)}


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
        # Label confirmed — return to training_pool unchanged
        segment.review_status = "training_pool"
        consensus_reached = True
        final_label = segment.effective_label
    elif disagree_n >= CONSENSUS_REQUIRED:
        # Label wrong — flip and return to training_pool
        flipped = OPPOSITE.get(segment.effective_label or "", segment.effective_label)
        segment.effective_label = flipped
        segment.review_status = "training_pool"
        consensus_reached = True
        final_label = flipped

    await db.commit()
    await db.refresh(vote)

    return ConsensusVoteOut(
        id=vote.id,
        segment_id=vote.segment_id,
        verdict=vote.verdict,
        voted_at=vote.voted_at,
        consensus_reached=consensus_reached,
        final_label=final_label,
    )
