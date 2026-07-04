# phase 2 — backend (python, local)

FastAPI service on the host, talking to the phase-1 Postgres on `localhost:5432`. No Docker, no k8s — that's phase 3+.

**Done when:** two different `X-User-Id`s each cast one vote on the same poll, the tally reflects both, and a duplicate vote from the same `X-User-Id` is rejected with `409`.

---

## stack

FastAPI · SQLAlchemy 2.x · Alembic · psycopg 3 · pydantic v2 + pydantic-settings · uvicorn · pytest + httpx.

---

## layout

```
app/
├─ voting/
│  ├─ main.py            # FastAPI app + router wiring
│  ├─ config.py          # pydantic-settings
│  ├─ db.py              # engine, SessionLocal, get_db
│  ├─ models.py          # SQLAlchemy: Poll, Option, Vote
│  ├─ schemas.py         # pydantic request/response
│  └─ routers/{health,polls}.py
├─ alembic/
│  ├─ env.py             # reads DATABASE_URL from env
│  └─ versions/0001_initial.py
├─ alembic.ini
├─ tests/{conftest,test_polls}.py
├─ pyproject.toml
└─ README.md
```

---

## delivery slices

One commit per slice. Don't advance until the demo passes.

### slice 1a — project init

- `app/pyproject.toml` with runtime deps (fastapi, uvicorn) — DB deps come in slice 1c.
- `app/voting/__init__.py`, `app/voting/main.py` — bare `FastAPI(title="voting")` with a single `GET /` returning `{"message": "hello world"}`.
- `app/.gitignore` — `__pycache__/`, `.venv/`, `*.egg-info/`, `.pytest_cache/`.
- **Proves:** the project is initialized and runnable.
- **Demo:** `uvicorn voting.main:app` starts; `curl /` → `200 {"message":"hello world"}`.

### slice 1b — health endpoint + router split

- `app/voting/routers/__init__.py`, `app/voting/routers/health.py` — `GET /healthz` → `{"status":"ok"}`.
- Wire the router in `main.py` via `include_router`. Drop `/` from `main.py` (its job — prove init — is done).
- **Proves:** the router pattern works and health checks return `200`.
- **Demo:** `curl /healthz` → `200 {"status":"ok"}`.

### slice 1c — DB config + connection

- Add DB deps to `pyproject.toml`: sqlalchemy, psycopg[binary], pydantic-settings. (alembic waits for slice 2.)
- `app/voting/config.py` — pydantic-settings `Settings` with `database_url` (default `postgresql+psycopg://voting:voting@localhost:5432/voting`).
- `app/voting/db.py` — `engine`, `SessionLocal`, `get_db()` dependency.
- **Proves:** the app can open a DB connection.
- **Demo:** `python -c "from voting.db import engine; from sqlalchemy import text; print(engine.connect().execute(text('SELECT 1')).scalar())"` prints `1` against the compose DB.

### slice 1d — readiness endpoint

- Extend `routers/health.py` with `GET /readyz` — runs `SELECT 1` via `get_db`; returns `{"status":"ready"}` on success, raises `HTTPException(503)` on failure.
- **Proves:** the app reports readiness based on real DB reachability.
- **Demo:** with compose DB up → `/readyz` → `200`; `docker compose stop postgres` → `/readyz` → `503`.

### slice 2 — models + alembic 0001

- `voting/models.py` in SQLAlchemy 2.x `Mapped[...]` style.
- `alembic/versions/0001_initial.py` **hand-written** to mirror `sql/01_schema.sql` exactly — columns, `uq_votes_poll_voter`, `idx_options_poll_id`, `idx_votes_poll_option`. Do not autogenerate.
- **Demo:** `alembic upgrade head` on a fresh DB produces a schema byte-identical to the SQL init path (verify via `pg_dump --schema-only` diff).

### slice 3 — poll create + read

- `voting/schemas.py` — `PollCreate`, `PollOut`, `OptionOut`.
- `voting/routers/polls.py` — `POST /polls`, `GET /polls`, `GET /polls/{id}` (detail eager-loads options via `selectinload`).
- **Demo:** `curl` create → `201`, list → returns it, detail → returns options.

### slice 4 — vote + tally

- Extend `schemas.py` with `VoteIn`, `VoteOut`, `ResultsOut`.
- Extend `routers/polls.py` with `POST /polls/{id}/vote` and `GET /polls/{id}/results` (see [vote semantics](#vote-semantics), [tally query](#tally-query)).
- **Demo:** two `X-User-Id`s vote different options → both `201`; same voter twice → `409`; results include zero-vote options. **This is the phase-2 "done when".**

### slice 5 — tests

- `tests/conftest.py` — real Postgres against `TEST_DATABASE_URL`, schema recreated per session, per-test transactional rollback, `TestClient` with `get_db` override.
- `tests/test_polls.py` — the [7 test cases](#test-cases).
- **Demo:** `pytest` green.

### slice 6 — dev docs

- `app/README.md` with the [local dev workflow](#local-dev-workflow).
- **Demo:** a fresh clone follows the README end-to-end with no extra questions.

---

## reference

### config

`voting/config.py` via `pydantic-settings`. No `.env` committed.

| Setting        | Env var        | Default                                                    |
| -------------- | -------------- | ---------------------------------------------------------- |
| `database_url` | `DATABASE_URL` | `postgresql+psycopg://voting:voting@localhost:5432/voting` |
| `log_level`    | `LOG_LEVEL`    | `INFO`                                                     |

Phase 3 swaps `DATABASE_URL` to the compose service name; phase 4 injects it via a k8s Secret. No code change per phase.

### data access

- One `Engine` per process, one `sessionmaker` in `voting/db.py`.
- `get_db()` yields a session, closes in `finally`.
- Eager-load anything returned across the request boundary (`selectinload(Poll.options)`) — no lazy loads on detached instances.

### endpoints

All JSON. `X-User-Id` required only on `POST /vote` (missing/blank → `400`).

| Method | Path                     | Body                              | Response (success)                                                              | Errors                                                                          |
| ------ | ------------------------ | --------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| POST   | `/polls`                 | `{title, options[], closes_at?}`  | `201 {id, title, options:[{id,label}], created_at, closes_at}`                  | `422` empty title or <2 options                                                 |
| GET    | `/polls`                 | —                                 | `200 [{id, title, created_at, closes_at}, ...]`                                 | —                                                                               |
| GET    | `/polls/{id}`            | —                                 | `200 {id, title, options:[{id,label}], created_at, closes_at}`                  | `404`                                                                           |
| POST   | `/polls/{id}/vote`       | `{option_id}`                     | `201 {poll_id, option_id, voter_id, created_at}`                                | `400` no `X-User-Id`; `403` closed; `404` poll/option not found; `409` duplicate |
| GET    | `/polls/{id}/results`    | —                                 | `200 {poll_id, total_votes, tallies:[{option_id, label, votes}, ...]}`          | `404`                                                                           |
| GET    | `/healthz`               | —                                 | `200 {"status":"ok"}`                                                           | —                                                                               |
| GET    | `/readyz`                | —                                 | `200 {"status":"ready"}` if `SELECT 1` works                                    | `503` DB unreachable                                                            |

### vote semantics

- **Closed** = `closes_at IS NOT NULL AND closes_at < now()`. App-enforced, not DB.
- **Duplicate** = same `(poll_id, voter_id)`. Pre-check with `SELECT` for a clean 409, but the `uq_votes_poll_voter` constraint is authoritative — catch `IntegrityError` for the race.
- **Cross-poll option** = `option_id` must belong to the poll in the URL. FKs alone allow the mismatch; app must reject with `404`.

### tally query

```sql
SELECT o.id, o.label, COUNT(v.id) AS votes
FROM options o
LEFT JOIN votes v ON v.option_id = o.id
WHERE o.poll_id = :poll_id
GROUP BY o.id, o.label
ORDER BY o.id;
```

`LEFT JOIN` so zero-vote options still appear.

### migrations

- `alembic init alembic` inside `app/`. `env.py` reads `DATABASE_URL` from env, not `alembic.ini`.
- `0001_initial.py` hand-written; verify against `sql/01_schema.sql` with `pg_dump --schema-only`.
- Clean slate: `docker compose down -v && docker compose up -d && alembic upgrade head`.
- `sql/01_schema.sql` stays as the raw-SQL onboarding path, but Alembic is now the source of truth.

### test cases

Real Postgres (not SQLite — unique/FK/cascade semantics differ). `TEST_DATABASE_URL` defaults to `postgresql+psycopg://voting:voting@localhost:5432/voting_test`.

1. Create poll with 3 options → `201`, IDs returned.
2. Two `X-User-Id`s vote different options → both `201`, tally is 1/1.
3. Same `X-User-Id` votes twice → second → `409`.
4. Vote with `option_id` from a different poll → `404`.
5. Vote on a poll with `closes_at` in the past → `403`.
6. `POST /vote` missing `X-User-Id` → `400`.
7. `GET /results` on a poll with zero votes → all options with `votes: 0`.

### local dev workflow

```sh
# terminal 1: DB (from repo root)
docker compose up -d

# terminal 2: app (from app/)
uv venv && uv pip install -e ".[dev]"    # or pip
alembic upgrade head
uvicorn voting.main:app --reload --port 8000

# smoke test
curl -s localhost:8000/healthz
curl -s -X POST localhost:8000/polls \
  -H 'content-type: application/json' \
  -d '{"title":"cloud?","options":["AWS","GCP","Azure"]}'
curl -s -X POST localhost:8000/polls/1/vote \
  -H 'content-type: application/json' -H 'X-User-Id: alice' \
  -d '{"option_id": 1}'
curl -s localhost:8000/polls/1/results
```

---

## out of scope

Auth (Cognito is phase 8-ish), rate limiting, CORS beyond `*`, Dockerfile (phase 3), metrics/tracing (phase 8), pagination on `GET /polls`.


---

## Development

### Init

```sh
cd app
python -m venv .venv
.\venv\Scripts\Activate.ps1
python.exe -m pip install --upgrade pip

# Installing build dependencies
pip install -e .


# start the server
uvicorn voting.main:app --port 8000
# INFO:     Started server process [22932]
# INFO:     Waiting for application startup.
# INFO:     Application startup complete.
# INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)

# confirm
curl http://localhost:8000/
# {"message":"hello world"}

# GET /healthz
curl http://localhost:8000/healthz
# {"status":"ok"}

curl http://localhost:8000/
# {"detail":"Not Found"}
```