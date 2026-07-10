# To-Do Demo App

Simple CRUD to-do list used to exercise the platform (Karpenter, EBS, Istio, ESO, ALBC, ArgoCD + Rollouts).

## Stack

- **api** — Node.js 20 + Express + `pg`
- **web** — React 18 + Vite (served by nginx in prod)
- **db**  — PostgreSQL 16

## Local smoke test

```bash
docker compose up --build
```

- Web:  http://localhost:8080
- API:  http://localhost:3000/api/todos
- Health: http://localhost:3000/healthz

## API

| Method | Path             | Body                    |
| ------ | ---------------- | ----------------------- |
| GET    | `/api/todos`     | —                       |
| POST   | `/api/todos`     | `{ "title": "..." }`    |
| PUT    | `/api/todos/:id` | `{ "title?", "done?" }` |
| DELETE | `/api/todos/:id` | —                       |

## Layout

```
to-do-app/
├── api/                # Node/Express source + Dockerfile
├── web/                # React/Vite source + Dockerfile + nginx.conf
├── db/init.sql         # schema + seed
├── docker-compose.yml  # local smoke test
└── charts/             # (step 3) Helm charts w/ Argo Rollouts
```

---

## Test

```sh
cd demo-app/to-do-app
docker compose up --build

curl localhost:8080/api/todos
# [{"id":3,"title":"Ship canary rollout","done":true,"created_at":"2026-07-09T23:41:06.404Z"},{"id":2,"title":"Wire up ArgoCD","done":true,"created_at":"2026-07-09T23:41:06.404Z"},{"id":1,"title":"Deploy EKS cluster","done":true,"created_at":"2026-07-09T23:41:06.404Z"}]


docker build -t simonangelfong/todo-app:api-v1  demo-app/to-do-app/api
docker push simonangelfong/todo-app:api-v1

docker build -t simonangelfong/todo-app:web-v1  demo-app/to-do-app/web
docker push simonangelfong/todo-app:web-v1

```

- join platform
  - projects/todo.yaml
  - workloads/todo-app.yaml

```sh
```