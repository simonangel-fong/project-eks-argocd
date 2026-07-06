import logging
from contextlib import asynccontextmanager
from importlib.metadata import version

from fastapi import FastAPI, HTTPException
from prometheus_fastapi_instrumentator import Instrumentator

from voting.db import ping
from voting.routers import polls

log = logging.getLogger("uvicorn.error")
APP_NAME = "voting api"
APP_VERSION = version("voting")


@asynccontextmanager
async def lifespan(_: FastAPI):
    ping()
    log.info("db ping ok (SELECT 1)")
    yield


app = FastAPI(title="Voting API", lifespan=lifespan)
app.include_router(polls.router)
Instrumentator().instrument(app).expose(app, endpoint="/metrics", include_in_schema=False)


@app.get("/")
def root():
    return {"app": APP_NAME, "version": APP_VERSION}


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
