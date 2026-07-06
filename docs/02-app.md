# App

- [App](#app)
  - [REST API](#rest-api)
  - [Development](#development)
    - [Init](#init)
    - [Flyway](#flyway)
    - [Poll](#poll)
    - [Vote](#vote)
    - [Result](#result)
  - [PyTest](#pytest)
  - [Containerize](#containerize)
  - [Push to DockerHub](#push-to-dockerhub)

---

## REST API

All JSON.
|

- metadata

| API            | Body | Response                                     |
| -------------- | ---- | -------------------------------------------- |
| `GET /`        | —    | `200 {"app":"voting api","version":"0.2.0"}` |
| `GET /healthz` | —    | `200 {"status":"ok"}`                        |
| `GET /readyz`  | —    | `200 {"status":"ready"}`                     |

- poll
  - `X-User-Id` header required only on `POST /vote` (missing/blank → `400`).

| API               | Body                             | Response                                                       |
| ----------------- | -------------------------------- | -------------------------------------------------------------- |
| `POST /polls`     | `{title, options[], closes_at?}` | `201 {id, title, options:[{id,label}], created_at, closes_at}` |
| `GET /polls`      |                                  | `200 [{id, title, created_at, closes_at}, ...]`                |
| `GET /polls/{id}` | —                                | `200 {id, title, options:[{id,label}], created_at, closes_at}` |

- vote

| API                     | Body          | Response                                         |
| ----------------------- | ------------- | ------------------------------------------------ |
| `POST /polls/{id}/vote` | `{option_id}` | `201 {poll_id, option_id, voter_id, created_at}` |

- results
- Tallies sorted by votes desc, then `option_id` asc. `total_votes` is the poll total, not the returned slice.

| API                       | Query               | Response                                                               |
| ------------------------- | ------------------- | ---------------------------------------------------------------------- |
| `GET /polls/{id}/results` | `limit=5` (`0`=all) | `200 {poll_id, total_votes, tallies:[{option_id, label, votes}, ...]}` |

---

- layout

```
app/
├─ voting/          # FastAPI package (config, db, models, schemas, routers)
├─ flyway/sql/      # Flyway migrations (V1__init.sql, V2__..., ...)
├─ tests/           # pytest
├─ pyproject.toml
└─ README.md
```

---

## Development

### Init

```sh
cd app
uv sync
uv run uvicorn voting.main:app --reload

curl http://127.0.0.1:8000/
# {"app":"voting api","version":"0.1.0"}

curl http://127.0.0.1:8000/healthz
# {"status":"ok"}

curl http://127.0.0.1:8000/readyz
# {"status":"ready"}

docker compose stop postgres
curl -i http://127.0.0.1:8000/readyz
```

---

### Flyway

```sh
docker compose down -v
docker compose up -d
docker compose logs flyway
# voting-flyway  | Database: jdbc:postgresql://postgres:5432/voting (PostgreSQL 16.14)
# voting-flyway  | Schema history table "public"."flyway_schema_history" does not exist yet
# voting-flyway  | Successfully validated 1 migration (execution time 00:00.027s)
# voting-flyway  | Creating Schema History table "public"."flyway_schema_history" ...
# voting-flyway  | Current version of schema "public": << Empty Schema >>
# voting-flyway  | Migrating schema "public" to version "1 - initial schema"
# voting-flyway  | Successfully applied 1 migration to schema "public", now at version v1 (execution time 00:00.081s)
```

---

### Poll

```sh
# happy path
curl -s -X POST http://127.0.0.1:8000/polls -H "content-type: application/json" -d "{\"title\":\"cats or dogs\",\"options\":[\"cats\",\"dogs\"]}"
# {"id":1,"title":"cats or dogs","created_at":"2026-07-04T21:27:00.402045Z","closes_at":null,"options":[{"id":1,"label":"cats"},{"id":2,"label":"dogs"}]}
curl -s http://127.0.0.1:8000/polls
# [{"id":1,"title":"cats or dogs","created_at":"2026-07-04T21:27:00.402045Z","closes_at":null}]
curl -s http://127.0.0.1:8000/polls/1
# {"id":1,"title":"cats or dogs","created_at":"2026-07-04T21:27:00.402045Z","closes_at":null,"options":[{"id":1,"label":"cats"},{"id":2,"label":"dogs"}]}

# alternative path
curl -s -X POST http://127.0.0.1:8000/polls -H "content-type: application/json" -d "{\"title\":\"\",\"options\":[\"a\",\"b\"]}"
# {"detail":[{"type":"value_error","loc":["body","title"],"msg":"Value error, title must not be empty","input":"","ctx":{"error":{}}}]}

curl -s -X POST http://127.0.0.1:8000/polls -H "content-type: application/json" -d "{\"title\":\"x\",\"options\":[\"a\",\"a\"]}"
# {"detail":[{"type":"value_error","loc":["body","options"],"msg":"Value error, duplicate option labels","input":["a","a"],"ctx":{"error":{}}}]}

```

---

### Vote

```sh
# happy path
curl -s -X POST http://127.0.0.1:8000/polls/1/vote -H "content-type: application/json" -H "X-User-Id: alice" -d "{\"option_id\":1}"
# {"poll_id":1,"option_id":1,"voter_id":"alice","created_at":"2026-07-04T21:30:58.142756Z"}

curl -s -X POST http://127.0.0.1:8000/polls/1/vote -H "content-type: application/json" -H "X-User-Id: bob"   -d "{\"option_id\":2}"
# {"poll_id":1,"option_id":2,"voter_id":"bob","created_at":"2026-07-04T21:31:18.943122Z"}

curl -s http://127.0.0.1:8000/polls/1/results
# {"poll_id":1,"total_votes":2,"tallies":[{"option_id":1,"label":"cats","votes":1},{"option_id":2,"label":"dogs","votes":1}]}

# alternative path
curl -i -X POST http://127.0.0.1:8000/polls/1/vote -H "content-type: application/json" -d "{\"option_id\":1}"
# HTTP/1.1 400 Bad Request
# date: Sat, 04 Jul 2026 21:32:14 GMT
# server: uvicorn
# content-length: 38
# content-type: application/json

# {"detail":"X-User-Id header required"}

curl -i -X POST http://127.0.0.1:8000/polls/1/vote -H "content-type: application/json" -H "X-User-Id: alice" -d "{\"option_id\":1}"
# HTTP/1.1 409 Conflict
# date: Sat, 04 Jul 2026 21:32:56 GMT
# server: uvicorn
# content-length: 27
# content-type: application/json

# {"detail":"duplicate vote"}

curl -i -X POST http://127.0.0.1:8000/polls/999/vote -H "content-type: application/json" -H "X-User-Id: x"  -d "{\"option_id\":1}"
# HTTP/1.1 404 Not Found
# date: Sat, 04 Jul 2026 21:33:15 GMT
# server: uvicorn
# content-length: 27
# content-type: application/json

# {"detail":"poll not found"}
```

---

### Result

```sh
curl -s http://127.0.0.1:8000/polls/1/results
# {"poll_id":1,"total_votes":10,"tallies":[{"option_id":1,"label":"Python","votes":3},{"option_id":2,"label":"Go","votes":3},{"option_id":3,"label":"TypeScript","votes":2},{"option_id":4,"label":"Rust","votes":2}]}

curl -s http://127.0.0.1:8000/polls/2/results
# {"poll_id":2,"total_votes":10,"tallies":[{"option_id":5,"label":"AWS","votes":4},{"option_id":6,"label":"Azure","votes":3},{"option_id":7,"label":"GCP","votes":3}]}
```

---

## PyTest

```sh
docker compose down -v
docker compose up -d

cd app
uv sync
uv run pytest -v
```

---

## Containerize

```sh
docker compose build api
docker compose up -d postgres
docker compose up flyway            # migrate
docker compose up -d api

curl http://127.0.0.1:8000/
# {"app":"voting api","version":"0.1.0"}
curl http://127.0.0.1:8000/healthz
# {"status":"ok"}
curl http://127.0.0.1:8000/readyz
# {"status":"ready"}

docker inspect --format "{{.State.Health.Status}}" voting-api
# healthy

```

---

## Push to DockerHub

```sh
docker login

docker build -t local-image app/

docker tag local-image:latest simonangelfong/voting-api:0.2.0
docker tag local-image:latest simonangelfong/voting-api:latest

# push both tags
docker push simonangelfong/voting-api:0.2.0
docker push simonangelfong/voting-api:latest
```
