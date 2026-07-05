# voting system — plan

## scope

- single voting service (polls, votes, results)
- postgres in-cluster on EBS (no RDS)
- no auth — trust `X-User-Id` header (Cognito later)
- EKS + ArgoCD (GitOps)

---

## stack

| layer      | choice                                                     |
| ---------- | ---------------------------------------------------------- |
| backend    | python 3.12, FastAPI, SQLAlchemy, psycopg                  |
| deps       | uv (`pyproject.toml` + `uv.lock`)                          |
| migrations | Flyway (shared by compose + Helm initContainer)            |
| db         | postgres 16                                                |
| k8s        | EKS, Helm, ArgoCD, Gateway API                             |
| iac        | terraform (VPC, EKS, IRSA, addons)                         |
| registry   | Docker Hub → ECR (before EKS)                              |
| ci         | GitHub Actions                                             |

---

## repo layout

```
project-eks-argocd/
├─ app/                   # FastAPI + Dockerfile + flyway/sql/
├─ helm/voting-app/       # chart + values-{dev,prod}.yaml
├─ argocd/                # root Application + apps/
├─ infra/aws/             # terraform (VPC, EKS, addons)
├─ docs/                  # 01-data, 02-app, 03-helm, 06-argocd, ...
├─ sql/initdb/            # local dev bootstrap
└─ docker-compose.yml
```

---

## api

```
POST   /polls                → create
GET    /polls                → list
GET    /polls/{id}           → details
POST   /polls/{id}/vote      → cast (X-User-Id)
GET    /polls/{id}/results   → tally
GET    /healthz /readyz      → probes
```

Details: [02-app.md](02-app.md).

---

## schema

```sql
polls    (id, title, created_at, closes_at)
options  (id, poll_id, label)
votes    (id, poll_id, option_id, voter_id, created_at,
          UNIQUE(poll_id, voter_id))    -- blocks double-vote
```

ERD + indexes: [01-data.md](01-data.md).

---

## phases

| #   | phase                    | status  | exit criteria                                          |
| --- | ------------------------ | ------- | ------------------------------------------------------ |
| 1   | data model (local)       | ✅ done | tally query returns correct counts                     |
| 2   | backend (python)         | ✅ done | two users vote, tally correct, tests green             |
| 3   | containerize             | ✅ done | `docker compose up` works from fresh clone             |
| 4   | helm chart (kind)        | ✅ done | `helm install` + `helm test` pass, data survives       |
| 5   | CI + ECR                 | ⏭ next  | push to `master` → image in ECR (immutable SHA tag)    |
| 6   | EKS (terraform)          |         | `gp3` default SC binds; Gateway API CRDs + GatewayClass ready |
| 7   | ArgoCD                   |         | root + children `Synced`/`Healthy`; new SHA auto-rolls |
| 8   | observability + hardening|         | dashboard shows RPS/errors/latency; `pg_dump` in S3    |

### phase 5 — CI + ECR

- move image Docker Hub → ECR
- Actions on `master`: build → tag `${sha}` → push (no `:latest`)

### phase 6 — EKS (terraform)

- modules: `terraform-aws-modules/{vpc,eks}/aws`
- addons: EBS CSI (IRSA), AWS Gateway API Controller, metrics-server
- `gp3` StorageClass, default, `WaitForFirstConsumer`, expandable
- node group AZ-aligned with postgres PVC (EBS is zonal)
- state: S3 + DynamoDB lock

### phase 7 — ArgoCD

Full breakdown: [06-argocd.md](06-argocd.md).

- TF installs ArgoCD; git owns everything past the root `Application`
- app-of-apps → ESO, ALBC + TargetGroupBinding, Karpenter, voting-app, cert-manager, external-dns
- SSO via AWS IdC

### phase 8 — ops

- `kube-prometheus-stack` via ArgoCD
- JSON logs → CloudWatch or Loki
- NetworkPolicies, PodSecurity, resource quotas
- `pg_dump` CronJob → S3 (nightly)

---

## persistence notes

- postgres = `StatefulSet`, 1 replica, `volumeClaimTemplate`
- PVC is zonal → pin nodes / affinity to the volume's AZ
- 5Gi dev / 20Gi prod on `gp3`
- backups = `pg_dump` CronJob (no RDS snapshots)

---

## principles

1. every phase ends demoable — never break the working state
2. inside-out: data → app → container → helm → CI → cluster → gitops → ops
3. commit at every exit criteria
4. one source of truth for SQL: `app/flyway/sql/V*.sql`
