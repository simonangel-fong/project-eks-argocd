from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from voting.db import get_db
from voting.models import Option, Poll, Vote
from voting.schemas import (
    PollCreate,
    PollDetail,
    PollResults,
    PollSummary,
    Tally,
    VoteCreate,
    VoteOut,
)

router = APIRouter(prefix="/polls", tags=["polls"])


@router.post("", response_model=PollDetail, status_code=status.HTTP_201_CREATED)
def create_poll(payload: PollCreate, db: Session = Depends(get_db)):
    poll = Poll(
        title=payload.title.strip(),
        closes_at=payload.closes_at,
        options=[Option(label=label) for label in payload.options],
    )
    db.add(poll)
    db.commit()
    db.refresh(poll)
    return poll


@router.get("", response_model=list[PollSummary])
def list_polls(db: Session = Depends(get_db)):
    return db.query(Poll).order_by(Poll.id).all()


@router.get("/{poll_id}", response_model=PollDetail)
def get_poll(poll_id: int, db: Session = Depends(get_db)):
    poll = (
        db.query(Poll)
        .options(selectinload(Poll.options))
        .filter(Poll.id == poll_id)
        .one_or_none()
    )
    if poll is None:
        raise HTTPException(status_code=404, detail="poll not found")
    return poll


@router.post("/{poll_id}/vote", response_model=VoteOut, status_code=status.HTTP_201_CREATED)
def cast_vote(
    poll_id: int,
    payload: VoteCreate,
    x_user_id: str | None = Header(default=None, alias="X-User-Id"),
    db: Session = Depends(get_db),
):
    if not x_user_id or not x_user_id.strip():
        raise HTTPException(status_code=400, detail="X-User-Id header required")

    poll = db.query(Poll).filter(Poll.id == poll_id).one_or_none()
    if poll is None:
        raise HTTPException(status_code=404, detail="poll not found")

    if poll.closes_at is not None and poll.closes_at <= datetime.now(timezone.utc):
        raise HTTPException(status_code=403, detail="poll closed")

    option = (
        db.query(Option)
        .filter(Option.id == payload.option_id, Option.poll_id == poll_id)
        .one_or_none()
    )
    if option is None:
        raise HTTPException(status_code=404, detail="option not found")

    vote = Vote(poll_id=poll_id, option_id=option.id, voter_id=x_user_id.strip())
    db.add(vote)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="duplicate vote")
    db.refresh(vote)
    return vote


@router.get("/{poll_id}/results", response_model=PollResults)
def get_results(poll_id: int, db: Session = Depends(get_db)):
    poll = (
        db.query(Poll)
        .options(selectinload(Poll.options))
        .filter(Poll.id == poll_id)
        .one_or_none()
    )
    if poll is None:
        raise HTTPException(status_code=404, detail="poll not found")

    counts = dict(
        db.query(Vote.option_id, func.count(Vote.id))
        .filter(Vote.poll_id == poll_id)
        .group_by(Vote.option_id)
        .all()
    )
    tallies = [
        Tally(option_id=o.id, label=o.label, votes=counts.get(o.id, 0))
        for o in poll.options
    ]
    return PollResults(
        poll_id=poll.id,
        total_votes=sum(t.votes for t in tallies),
        tallies=tallies,
    )
