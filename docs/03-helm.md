# Helm

- [Helm](#helm)
  - [layout](#layout)
  - [chart resources](#chart-resources)
  - [values contract](#values-contract)
    - [`values-dev.yaml` — local kind/minikube](#values-devyaml--local-kindminikube)
    - [`values-prod.yaml` — prod-shaped](#values-prodyaml--prod-shaped)
  - [delivery phase](#delivery-phase)
  - [Development](#development)
    - [Gateway](#gateway)

---

- **Goal:** package the voting API + Postgres + Flyway migrations into a single Helm chart that installs on a local kind/minikube cluster, routed via the **Gateway API**.
- **Done when:**
  - `helm install voting ./helm/voting-app -f values-dev.yaml` brings the stack up.
  - `curl` through the Gateway hits the API and votes tally correctly.
  - Deleting the Postgres pod → data survives (PVC-backed).
  - The same chart installs cleanly with `values-prod.yaml` (different image tag, host, replicas, resources).

---

## layout

```
helm/
└─ voting-app/
   ├─ Chart.yaml
   ├─ values.yaml            # defaults
   ├─ values-dev.yaml        # overlay: local kind/minikube
   ├─ values-prod.yaml       # overlay: prod-shaped (EKS-ready)
   ├─ .helmignore
   └─ templates/
      ├─ _helpers.tpl                 # name, fullname, labels, selectorLabels
      ├─ NOTES.txt                    # post-install instructions
      ├─ 01-configmap.yaml            # non-secret API config (DATABASE host/port/db)
      ├─ 02-secret.yaml               # DB user / password (opt-in create)
      ├─ 03-deployment.yaml           # Deployment + Flyway initContainer
      ├─ 04-service.yaml              # ClusterIP :8000
      ├─ 05-gateway.yaml              # gateway.networking.k8s.io/v1 Gateway (toggleable)
      ├─ 06-httproute.yaml            # gateway.networking.k8s.io/v1 HTTPRoute → Service
      ├─ 07-hpa.yaml                  # optional HPA (prod overlay)
      ├─ postgres-secret.yaml         # POSTGRES_USER / _PASSWORD / _DB
      ├─ postgres-statefulset.yaml    # single replica, volumeClaimTemplate
      ├─ postgres-service.yaml        # headless ClusterIP
      └─ tests/
         └─ test-connection.yaml      # `helm test` — hits /readyz
```

Chart name: `voting-app`. Release name in dev: `voting`.

**Prereq (out of chart).** The Gateway API CRDs are cluster-scoped and must exist _before_ the chart installs:

```sh
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
```

The chart does **not** install CRDs (avoids ownership conflicts with ArgoCD + prod clusters). It renders `Gateway` + `HTTPRoute` and expects a `GatewayClass` to already exist. Chart gates rendering behind `gateway.enabled` and skips with a clear `NOTES.txt` warning if the CRD is missing.

---

## chart resources

| Kind        | Name (fullname-prefixed) | Purpose                                                                           |
| ----------- | ------------------------ | --------------------------------------------------------------------------------- |
| ConfigMap   | `voting-api`             | Non-secret env: `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`                 |
| Secret      | `voting-api`             | `DATABASE_USER`, `DATABASE_PASSWORD` (created unless `existingSecret` is set)     |
| Deployment  | `voting-api`             | FastAPI pod; **initContainer** runs Flyway `migrate` before the API starts        |
| Service     | `voting-api`             | ClusterIP → `:8000`                                                               |
| Gateway     | `voting-api`             | `gateway.networking.k8s.io/v1` — listener :80 HTTP (toggle via `gateway.enabled`) |
| HTTPRoute   | `voting-api`             | Host-based routing to the Service; attaches to the Gateway via `parentRefs`       |
| HPA         | `voting-api`             | Optional; enabled in `values-prod.yaml`                                           |
| Secret      | `voting-postgres`        | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`                               |
| StatefulSet | `voting-postgres`        | 1 replica, `volumeClaimTemplate` for `/var/lib/postgresql/data`                   |
| Service     | `voting-postgres`        | Headless ClusterIP → `:5432` (stable DNS for the StatefulSet pod)                 |
| Test Pod    | `voting-api-test`        | `helm test` probe → curls `/readyz` and expects `200`                             |

**DATABASE_URL wiring** — assembled at Deployment time from ConfigMap + Secret so credentials are never rendered into the ConfigMap:

```
postgresql+psycopg://$(DATABASE_USER):$(DATABASE_PASSWORD)@$(DATABASE_HOST):$(DATABASE_PORT)/$(DATABASE_NAME)
```

**Flyway as initContainer** — same image + same SQL as `docker-compose.yml`:

```yaml
initContainers:
  - name: flyway
    image: flyway/flyway:10-alpine
    args:
      - -url=jdbc:postgresql://$(DATABASE_HOST):$(DATABASE_PORT)/$(DATABASE_NAME)
      - -user=$(DATABASE_USER)
      - -password=$(DATABASE_PASSWORD)
      - -connectRetries=30
      - migrate
    volumeMounts:
      - name: flyway-sql
        mountPath: /flyway/sql
        readOnly: true
volumes:
  - name: flyway-sql
    configMap:
      name: voting-flyway-sql
```

**Migration SQL delivery** — `app/flyway/sql/V*.sql` files are packaged into a ConfigMap at chart-build time. Two options; pick one in phase 4.3:

1. **In-chart ConfigMap** (`voting-flyway-sql`) generated via `.Files.Glob "flyway-sql/*.sql"` — copy `app/flyway/sql/` into `helm/voting-app/flyway-sql/` (or symlink). Simplest for local.
2. **Baked-in-image** — build a Flyway image `FROM flyway/flyway:10-alpine` that `COPY`s the SQL. Cleaner for EKS/ArgoCD later; defer to phase 5.

Start with option 1.

**Gateway + HTTPRoute shape** — the app owns both. In multi-team clusters, the platform team owns the `Gateway` and apps only ship `HTTPRoute` — that split is worth doing at phase 7 (EKS/ArgoCD), not phase 4. Keep both in-chart for now, gate the Gateway behind `gateway.createGateway: true` so the same chart can attach to an external Gateway later without a rewrite.

```yaml
# templates/05-gateway.yaml (rendered only if gateway.enabled AND gateway.createGateway)
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: {{ include "voting-app.fullname" . }}
spec:
  gatewayClassName: {{ .Values.gateway.className }}
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: Same
---
# templates/06-httproute.yaml (rendered if gateway.enabled)
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ include "voting-app.fullname" . }}
spec:
  parentRefs:
    - name: {{ .Values.gateway.parentRef.name | default (include "voting-app.fullname" .) }}
      {{- with .Values.gateway.parentRef.namespace }}
      namespace: {{ . }}
      {{- end }}
      sectionName: http
  hostnames:
    - {{ .Values.gateway.host | quote }}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: {{ include "voting-app.fullname" . }}
          port: {{ .Values.service.port }}
```

---

## values contract

`values.yaml` (defaults, safe for CI dry-run):

```yaml
image:
  repository: voting-api
  tag: local # overridden per env
  pullPolicy: IfNotPresent

replicaCount: 1

resources:
  requests: { cpu: 50m, memory: 128Mi }
  limits: { cpu: 500m, memory: 512Mi }

service:
  type: ClusterIP
  port: 8000

gateway:
  enabled: false
  createGateway: true # false → chart only renders HTTPRoute, attaches to external Gateway
  className: nginx # e.g. nginx, envoy, aws-alb (prod), cilium
  host: voting.local
  parentRef:
    name: "" # defaults to fullname when createGateway=true
    namespace: "" # required only if the Gateway lives in another namespace
  annotations: {}

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 3
  targetCPUUtilizationPercentage: 70

postgres:
  enabled: true # off if pointing at external DB later
  image:
    repository: postgres
    tag: "16-alpine"
  auth:
    username: voting
    password: voting # dev only; overlay in prod
    database: voting
    existingSecret: "" # if set, chart skips creating postgres-secret
  persistence:
    enabled: true
    size: 5Gi
    storageClass: "" # "" = default SC
    accessModes: [ReadWriteOnce]
  resources:
    requests: { cpu: 100m, memory: 256Mi }
    limits: { cpu: 1, memory: 1Gi }

flyway:
  enabled: true
  image:
    repository: flyway/flyway
    tag: "10-alpine"
  connectRetries: 30

api:
  env: [] # extra env vars, list of {name, value}
```

### `values-dev.yaml` — local kind/minikube

```yaml
image:
  tag: local
gateway:
  enabled: true
  createGateway: true
  className: nginx # nginx-gateway-fabric locally
  host: voting.local
postgres:
  persistence:
    size: 2Gi
```

### `values-prod.yaml` — prod-shaped

```yaml
image:
  repository: simonangelfong/voting-api:latest
  tag: "REPLACE_ME_SHA"
  pullPolicy: IfNotPresent
replicaCount: 2
autoscaling:
  enabled: true
gateway:
  enabled: true
  createGateway: false # attach to platform-owned Gateway
  className: aws-alb # AWS Gateway API Controller
  host: voting.example.com
  parentRef:
    name: platform-gateway
    namespace: gateway-system
postgres:
  auth:
    existingSecret: voting-postgres-prod # created out-of-band
  persistence:
    size: 20Gi
    storageClass: gp3
  resources:
    requests: { cpu: 500m, memory: 1Gi }
    limits: { cpu: 2, memory: 4Gi }
```

---

## delivery phase

| #   | phase             | description                                                                                  |
| --- | ----------------- | -------------------------------------------------------------------------------------------- |
| 4.1 | init              | `helm create voting-app`, strip but keep deployment, nginx web.                              |
| 4.2 | postgres          | StatefulSet + PVC + headless Service + Secret; `helm install` → pod `Running`, PVC `Bound`   |
| 4.3 | flyway configmap  | package `V*.sql` into `voting-flyway-sql` ConfigMap via `.Files.Glob`                        |
| 4.4 | persistence proof | delete Postgres pod → new pod re-mounts PVC → poll data is still there                       |
| 4.5 | api deployment    | Deployment with Flyway initContainer + Service; readiness probe on `/readyz` returns `200`   |
| 4.6 | gateway + route   | `Gateway` + `HTTPRoute` templates gated by `gateway.enabled`; `curl -H "Host: voting.local"` |
| 4.7 | helm test         | `templates/tests/test-connection.yaml` hits `/readyz`; `helm test voting` passes             |
| 4.8 | package + version | bump `Chart.yaml` `version`/`appVersion`, `helm package`, tag commit                         |

**Lint at every step, not at the end.** Each sub-phase's done-line implicitly requires.

```sh
helm lint ./helm/voting-app
helm template voting ./helm/voting-app -f values-dev.yaml | kubectl apply --dry-run=client -f -
```

If either fails, the sub-phase is not done. Commit at every done-line. Never break `helm install` on `master`.

**Gateway API assumptions.**

- Gateway API CRDs (`v1`) are installed cluster-wide, out of chart.
- A `GatewayClass` matching `values.gateway.className` exists and is `Accepted`.
- The Gateway controller (nginx-gateway-fabric locally, AWS Gateway API Controller in prod) is running.
- Chart renders `Gateway` only when `gateway.createGateway: true`; otherwise it only ships an `HTTPRoute` with a `parentRef` to a Gateway the platform owns.

---

## Development

```sh
helm lint ./helm/voting-app

helm install voting ./helm/voting-app -f ./helm/voting-app/values-dev.yaml
kubectl port-forward svc/voting-voting-app-api 8080:80
curl http://127.0.0.1:8080/

helm upgrade -i voting ./helm/voting-app -f ./helm/voting-app/values-dev.yaml
kubectl get pod voting-voting-app-postgres-0
# NAME                           READY   STATUS    RESTARTS   AGE
# voting-voting-app-postgres-0   1/1     Running   0          27s

kubectl get pvc data-voting-voting-app-postgres-0
# NAME                                STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
# data-voting-voting-app-postgres-0   Bound    pvc-d30ffbaa-2877-4322-b100-72a953602cb6   2Gi        RWO            standard       <unset>                 40s

helm upgrade -i voting ./helm/voting-app -f ./helm/voting-app/values-dev.yaml
kubectl get cm voting-flyway-sql -o jsonpath='{.data.V1__initial_schema\.sql}' | head
# CREATE TABLE polls (
#     id          BIGSERIAL PRIMARY KEY,
#     title       TEXT        NOT NULL,
#     created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
#     closes_at   TIMESTAMPTZ
# );

# CREATE TABLE options (
#     id       BIGSERIAL PRIMARY KEY,
#     poll_id  BIGINT NOT NULL REFERENCES polls(id) ON DELETE CASCADE,


# confirm pgdb persistent
kubectl exec -i voting-voting-app-postgres-0 -- psql -U voting -d voting <<'SQL'
CREATE TABLE IF NOT EXISTS persistence_probe (id serial PRIMARY KEY, note text, at timestamptz default now());
INSERT INTO persistence_probe (note) VALUES ('before pod delete');
SELECT * FROM persistence_probe;
SQL
#  id |       note        |              at
# ----+-------------------+-------------------------------
#   1 | before pod delete | 2026-07-05 02:29:50.154622+00
# (1 row)

#  Delete the pod, wait for the StatefulSet to recreate it
kubectl delete pod voting-voting-app-postgres-0
# pod "voting-voting-app-postgres-0" deleted from default namespace
kubectl wait --for=condition=Ready pod/voting-voting-app-postgres-0 --timeout=90s
# pod/voting-voting-app-postgres-0 condition met

# Read it back
kubectl exec -i voting-voting-app-postgres-0 -- psql -U voting -d voting -c "SELECT * FROM persistence_probe;"
#  id |       note        |              at
# ----+-------------------+-------------------------------
#   1 | before pod delete | 2026-07-05 02:29:50.154622+00
# (1 row)


helm upgrade -i voting ./helm/voting-app -f ./helm/voting-app/values-dev.yaml
kubectl rollout status deploy/voting-voting-app-api --timeout=120s
# deployment "voting-voting-app-api" successfully rolled out
kubectl port-forward svc/voting-voting-app-api 8000:8000
curl -s http://127.0.0.1:8000/readyz
# {"status":"ready"}
```

### Gateway

```sh
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

helm install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric   --create-namespace -n nginx-gateway

k get gatewayclass
# NAME    CONTROLLER                                   ACCEPTED   AGE
# nginx   gateway.nginx.org/nginx-gateway-controller   True       11s

helm upgrade -i voting ./helm/voting-app -f ./helm/voting-app/values-dev.yaml

kubectl get gateway voting-voting-app-api
# NAME                    CLASS   ADDRESS   PROGRAMMED   AGE
# voting-voting-app-api   nginx             True         6s

kubectl get httproute voting-voting-app-api -o wide
# NAME                    HOSTNAMES          AGE
# voting-voting-app-api   ["voting.local"]   22s

kubectl get svc -n nginx-gateway
# NAME                       TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
# ngf-nginx-gateway-fabric   ClusterIP   10.96.152.137   <none>        443/TCP   93s

# clean up
helm uninstall voting
kubectl delete pvc data-voting-voting-app-postgres-0
```

runbook

```sh
# debug flyway
kubectl logs voting-voting-app-api-765b494888-tsr9x -c flyway

```

---

test

```sh
helm upgrade -i voting ./helm/voting-app -f ./helm/voting-app/values-dev.yaml
helm test voting
# NAME: voting
# LAST DEPLOYED: Sat Jul  4 22:54:47 2026
# NAMESPACE: default
# STATUS: deployed
# REVISION: 7
# DESCRIPTION: Upgrade complete
# TEST SUITE:     voting-voting-app-api-test
# Last Started:   Sat Jul  4 22:55:08 2026
# Last Completed: Sat Jul  4 22:55:14 2026
# Phase:          Succeeded
```