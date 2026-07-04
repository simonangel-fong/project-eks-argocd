from datetime import datetime, timezone

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class PollCreate(BaseModel):
    title: str
    options: list[str]
    closes_at: datetime | None = None

    @field_validator("title")
    @classmethod
    def title_not_blank(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("title must not be empty")
        return v

    @field_validator("options")
    @classmethod
    def options_shape(cls, v: list[str]) -> list[str]:
        cleaned = [o.strip() for o in v]
        if any(not o for o in cleaned):
            raise ValueError("option labels must not be empty")
        if len(cleaned) < 2:
            raise ValueError("at least 2 options required")
        if len(set(cleaned)) != len(cleaned):
            raise ValueError("duplicate option labels")
        return cleaned

    @model_validator(mode="after")
    def closes_at_not_past(self):
        if self.closes_at is not None:
            now = datetime.now(timezone.utc)
            ca = self.closes_at
            if ca.tzinfo is None:
                ca = ca.replace(tzinfo=timezone.utc)
            if ca <= now:
                raise ValueError("closes_at must be in the future")
        return self


class OptionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    label: str


class PollSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    title: str
    created_at: datetime
    closes_at: datetime | None


class PollDetail(PollSummary):
    options: list[OptionOut] = Field(default_factory=list)


class VoteCreate(BaseModel):
    option_id: int


class VoteOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    poll_id: int
    option_id: int
    voter_id: str
    created_at: datetime


class Tally(BaseModel):
    option_id: int
    label: str
    votes: int


class PollResults(BaseModel):
    poll_id: int
    total_votes: int
    tallies: list[Tally]
