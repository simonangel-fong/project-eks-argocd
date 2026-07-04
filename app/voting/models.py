from datetime import datetime

from sqlalchemy import BigInteger, DateTime, ForeignKey, Text, UniqueConstraint, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


class Poll(Base):
    __tablename__ = "polls"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    closes_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    options: Mapped[list["Option"]] = relationship(
        back_populates="poll", cascade="all, delete-orphan", order_by="Option.id"
    )


class Option(Base):
    __tablename__ = "options"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    poll_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("polls.id", ondelete="CASCADE"), nullable=False
    )
    label: Mapped[str] = mapped_column(Text, nullable=False)

    poll: Mapped[Poll] = relationship(back_populates="options")


class Vote(Base):
    __tablename__ = "votes"
    __table_args__ = (UniqueConstraint("poll_id", "voter_id", name="uq_votes_poll_voter"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    poll_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("polls.id", ondelete="CASCADE"), nullable=False
    )
    option_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("options.id", ondelete="CASCADE"), nullable=False
    )
    voter_id: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
