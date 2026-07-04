import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException

from voting.db import ping
from voting.routers import polls

log = logging.getLogger("uvicorn.error")


@asynccontextmanager
async def lifespan(_: FastAPI):
    ping()
    log.info("db ping ok (SELECT 1)")
    yield


app = FastAPI(title="Voting API", lifespan=lifespan)
app.include_router(polls.router)


@app.get("/")
def root():
    return {"message": "hello world"}


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    try:
        ping()
    except Exception:
        raise HTTPException(status_code=503, detail="db unreachable")
    return {"status": "ready"}
