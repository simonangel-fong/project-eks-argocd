# Multi-tenant Platform Document - Onboarding

[Back](../README.md)

- [Multi-tenant Platform Document - Onboarding](#multi-tenant-platform-document---onboarding)
  - [Onboarding](#onboarding)
  - [Demo - Team A](#demo---team-a)
  - [Demo - Team B](#demo---team-b)

---

## Onboarding

**What the tenant brings**

1. Team name (`<team>`) — used as namespace, subdomain, and label.
2. Git repo containing manifests.

**What the tenant deploys** in tenant's repo:

- `Deployment` / `StatefulSet` with `team` label, `resources`, and probes.
- `PVC` (if stateful) referencing `gp3` or `gp3-iops`.
- `Service` fronting the pods.
- `HTTPRoute` attached to `istio-ingress/istio-ingress`, hostname under `<team>.arguswatcher.net`.

---

## Demo - Team A

**Profile.** Simple stateless web app. Default path only — no PVC, no toleration, one hostname.

**Capabilities exercised:** compute (`general`), ingress + TLS + DNS.

- Application
  - simple nginx web app
  - stateless
  - default nginx
  - file: `demo-app/team-a`
  - host: `team-a.arguswatcher.net`

**Tenant manifests**

```yaml
# demo-app/team-a/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: team-a
  labels: { team: team-a, app: web }
spec:
  replicas: 2
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { team: team-a, app: web } }
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports: [{ containerPort: 80, name: http }]
          resources: { requests: { cpu: 50m, memory: 64Mi } }
          readinessProbe: { httpGet: { path: /, port: http } }
          livenessProbe: { httpGet: { path: /, port: http } }
---
apiVersion: v1
kind: Service
metadata: { name: web, namespace: team-a }
spec:
  selector: { app: web }
  ports: [{ port: 80, targetPort: http, name: http }]
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: web, namespace: team-a }
spec:
  parentRefs: [{ name: istio-ingress, namespace: istio-ingress }]
  hostnames: [team-a.arguswatcher.net]
  rules:
    - backendRefs: [{ name: web, port: 80 }]
```

---

## Demo - Team B

**Profile.** Full-stack to-do app: web tier (stateless) + Postgres (stateful, PVC). Exercises two node classes and high-IOPS block storage.

**Capabilities exercised:**

- compute (`general` + `database`)
- storage (`gp3-iops`, `Retain`)
- ingress + TLS + DNS.

- Application
  - full-stack to-do app
  - stateful, PVC
  - file: `demo-app/team-b` (renamed from `demo-app/to-do-app`)
  - host: `team-b.arguswatcher.net`

**Tenant manifests**

```yaml
# Postgres — database class, gp3-iops PVC
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: team-b
  labels: { team: team-b, app: postgres }
spec:
  serviceName: postgres
  replicas: 1
  selector: { matchLabels: { app: postgres } }
  template:
    metadata: { labels: { team: team-b, app: postgres } }
    spec:
      nodeSelector: { workload-class: database }
      tolerations:
        - { key: workload-class, value: database, effect: NoSchedule }
      containers:
        - name: postgres
          image: postgres:16
          env:
            - { name: POSTGRES_PASSWORD, value: changeme } # ESO in a later phase
          ports: [{ containerPort: 5432, name: pg }]
          volumeMounts: [{ name: data, mountPath: /var/lib/postgresql/data }]
          resources: { requests: { cpu: 250m, memory: 512Mi } }
  volumeClaimTemplates:
    - metadata: { name: data }
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: gp3-iops
        resources: { requests: { storage: 20Gi } }
---
apiVersion: v1
kind: Service
metadata: { name: postgres, namespace: team-b }
spec:
  clusterIP: None
  selector: { app: postgres }
  ports: [{ port: 5432, targetPort: pg, name: pg }]
---
# Web tier — general class, no toleration
apiVersion: apps/v1
kind: Deployment
metadata:
  name: todo
  namespace: team-b
  labels: { team: team-b, app: todo }
spec:
  replicas: 2
  selector: { matchLabels: { app: todo } }
  template:
    metadata: { labels: { team: team-b, app: todo } }
    spec:
      containers:
        - name: todo
          image: ghcr.io/team-b/todo:1.0.0
          ports: [{ containerPort: 8080, name: http }]
          env:
            - { name: DB_HOST, value: postgres.team-b.svc.cluster.local }
          resources: { requests: { cpu: 100m, memory: 128Mi } }
          readinessProbe: { httpGet: { path: /healthz, port: http } }
          livenessProbe: { httpGet: { path: /healthz, port: http } }
---
apiVersion: v1
kind: Service
metadata: { name: todo, namespace: team-b }
spec:
  selector: { app: todo }
  ports: [{ port: 80, targetPort: http, name: http }]
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: todo, namespace: team-b }
spec:
  parentRefs: [{ name: istio-ingress, namespace: istio-ingress }]
  hostnames: [team-b.arguswatcher.net]
  rules:
    - backendRefs: [{ name: todo, port: 80 }]
```
