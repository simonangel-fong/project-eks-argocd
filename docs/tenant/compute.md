# Multi-tenant Platform Guide - Compute

[Back](../../README.md)

- [Multi-tenant Platform Guide - Compute](#multi-tenant-platform-guide---compute)
  - [Overview](#overview)
  - [Workload Class](#workload-class)
  - [How to Request Compute](#how-to-request-compute)
  - [Examples](#examples)
  - [Rules of the Road](#rules-of-the-road)

---

## Overview

The platform ships out-of-the-box compute capability.Tenants pick a **workload class** by setting a `nodeSelector`, and — for tainted classes — a matching `toleration`. Nodes appear when a pod is scheduled and disappear when the pod is gone.

---

## Workload Class

| Class      | Common usage                                             | Toleration required? |
| ---------- | -------------------------------------------------------- | :------------------: |
| `general`  | Stateless (web apps, APIs, workers). **Default choice.** |          No          |
| `database` | Stateful with a PVC (databases, queues, caches).         |         Yes          |
| `gpu`      | GPU-backed (inference, training).                        |         Yes          |

---

## How to Request Compute

Add a `nodeSelector` to the pod spec.

- If the class has a taint, add the matching `toleration`.
- no instance sizes, no `nodeAffinity`, no capacity-type flags.

```yaml
spec:
  nodeSelector:
    workload-class: <general|database|gpu>
  tolerations: # omit for `general`
    - key: workload-class
      value: <database|gpu>
      effect: NoSchedule
```

---

## Examples

**Stateless web app — `general`:**

```yaml
spec:
  nodeSelector:
    workload-class: general
  containers:
    - name: web
      image: nginx:1.27
      resources:
        requests: { cpu: 100m, memory: 128Mi }
      readinessProbe: { httpGet: { path: /, port: 80 } }
      livenessProbe: { httpGet: { path: /, port: 80 } }
```

**Postgres — `database`:**

```yaml
spec:
  nodeSelector:
    workload-class: database
  tolerations:
    - { key: workload-class, value: database, effect: NoSchedule }
  containers:
    - name: postgres
      image: postgres:16
      resources:
        requests: { cpu: 250m, memory: 512Mi }
```

---

## Rules of the Road

- **Always declare `resources.requests`** — Kyverno rejects pods without CPU + memory requests.
- **Always declare probes** — `readinessProbe` and `livenessProbe` are required.
- **Never pin instance types or AZs** — the platform selects hardware; pinning breaks autoscaling and fails admission.
- **Nodes recycle every 30 days** for AMI patching. Pods can restart at any time; use a `PodDisruptionBudget` to keep a minimum available replica count.
- **Spot on `general`** — the platform mixes spot + on-demand for cost. Workloads that cannot tolerate interruption should use `database`.
- **HPA is tenant-owned** — the platform ships `metrics-server`; tenants write their own `HorizontalPodAutoscaler`.
- **Pending pod?** Verify the `nodeSelector` value matches a valid class and, for tainted classes, that the toleration is present. If still pending, contact the platform team.
