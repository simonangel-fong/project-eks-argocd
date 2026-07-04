from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from voting.db import get_db

# init router
router = APIRouter(tags=["health"])


# GET /healthz/
@router.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}


# GET /readyz/
@router.get("/readyz")
def readyz(db: Session = Depends(get_db)) -> dict[str, str]:
    try:
        db.execute(text("SELECT 1"))
    except SQLAlchemyError:
        raise HTTPException(status_code=503, detail="db unreachable")
    return {"status": "ready"}
