# Multi-tenant Cluster Capabilities: Compute

[Back](../README.md)

- [Multi-tenant Cluster Capabilities: Compute](#multi-tenant-cluster-capabilities-compute)
  - [Compute capability](#compute-capability)
    - [Responsibility model](#responsibility-model)
    - [Node classification](#node-classification)
  - [Tenant consumption pattern](#tenant-consumption-pattern)
  - [Platform ↔ tenant interactions](#platform--tenant-interactions)
  - [Demos](#demos)
      - [Open items](#open-items)

---

## Compute capability

platform provide out of the box compute capability

### Responsibility model

| Concern                                       | Platform | Tenant | Notes                                                                            |
| --------------------------------------------- | :------: | :----: | -------------------------------------------------------------------------------- |
| Cluster and NodePool definitions              |    ✅    |        | Terraform manages EKS; Karpenter `NodePool` + `EC2NodeClass` are GitOps-managed. |
| Node autoscaling and consolidation            |    ✅    |        | Karpenter reconciles to pending pod demand.                                      |
| Node lifecycle (AMI, patching, expiry)        |    ✅    |        | `expireAfter: 720h` forces monthly recycling; AMI pinned to `al2023@latest`.     |
| Workload-class contract (labels + taints)     |    ✅    |        | Stable across releases; documented in the onboarding manual.                     |
| Pod spec, resource requests / limits          |          |   ✅   | Tenants declare what they need; platform admits or rejects via Kyverno.          |
| Placement hints (`nodeSelector`, tolerations) |          |   ✅   | Tenants opt into a workload class; they never name instance types.               |
| HPA / KEDA scaling rules                      |          |   ✅   | Tenants own their scaling behavior; platform ships `metrics-server`.             |

### Node classification

Four workload classes, each identified by the label `workload-class=<class>`. Tenant pods select a class; instance-type selection remains a platform decision.

| Class      | Label                     | Provisioned by                     | Taint (if any)                       | Capacity types   | Instance families | Purpose                                                                                             |
| ---------- | ------------------------- | ---------------------------------- | ------------------------------------ | ---------------- | ----------------- | --------------------------------------------------------------------------------------------------- |
| `platform` | `workload-class=platform` | EKS managed node group + Karpenter | `workload-class=platform:NoSchedule` | on-demand        | m / t (bootstrap) | Bootstraps the cluster and runs platform components (Karpenter, Istio, ArgoCD, Prometheus, ESO, …). |
| `general`  | `workload-class=general`  | Karpenter                          | none                                 | on-demand + spot | t, m (gen > 3)    | Default class for stateless tenant workloads.                                                       |
| `database` | `workload-class=database` | Karpenter                          | `workload-class=database:NoSchedule` | on-demand only   | m, r (gen > 5)    | Stateful tenant workloads: databases, queues, caches with PVCs.                                     |
| `gpu`      | `workload-class=gpu`      | Karpenter                          | `workload-class=gpu:NoSchedule`      | on-demand        | g5 / g6           | ML / AI workloads. Defined but not provisioned until requested.                                     |

The `platform` class is a hybrid by necessity:

- An **EKS managed node group** (`role=bootstrap`, `workload-class=platform`, `karpenter.sh/controller=true`, tainted `workload-class=platform:NoSchedule`, defined in [infra/11-eks.tf](infra/11-eks.tf)) provides the always-on capacity that Karpenter itself needs in order to run. Without it, there is a chicken-and-egg problem — Karpenter cannot provision the nodes that host Karpenter.
- A **Karpenter `platform` NodePool** (target state) extends the class elastically for the rest of the platform components, carrying the same label and taint.

Both are treated as one logical class from the tenant's perspective: anything labeled `workload-class=platform`. Because the bootstrap group is tainted, every platform component that lands there must declare the matching toleration — including EKS managed add-ons (`coredns`, `metrics-server`) whose toleration is injected via add-on `configuration_values`; the DaemonSet add-ons (`vpc-cni`, `kube-proxy`, `eks-pod-identity-agent`) tolerate all taints by default.

Design principles:

- **Opt-in via taints.** Every specialized class carries a matching taint so that only workloads that explicitly tolerate it land there. `general` has no taint and acts as the default.
- **No per-tenant nodes.** All tenants share the same pool within a class. Isolation happens at the namespace / NetworkPolicy / mTLS layer, not at the node layer.
- **Platform isolation is one-way.** The `platform` taint fences tenant pods out because they never receive the toleration. Kyverno additionally rejects tenant pods that try to set `nodeSelector.workload-class: platform`, so isolation is both taint-enforced and policy-enforced.
- **Consolidation policy varies by class.** `general` consolidates aggressively (`WhenEmptyOrUnderutilized`, 30s); `database` consolidates conservatively (`WhenEmpty`, 5 min, 1-node disruption budget) to protect stateful workloads. The bootstrap managed group does not consolidate — it is fixed-size.

---

## Tenant consumption pattern

Tenants request compute by combining a `nodeSelector` with a matching `toleration` (only required for tainted classes). They never reference instance families, sizes, or capacity types directly.

```yaml
# general (default) — nodeSelector only
spec:
  nodeSelector:
    workload-class: general
```

```yaml
# database — nodeSelector + toleration
spec:
  nodeSelector:
    workload-class: database
  tolerations:
    - key: workload-class
      value: database
      effect: NoSchedule
```

```yaml
# gpu — nodeSelector + toleration + resource request
spec:
  nodeSelector:
    workload-class: gpu
  tolerations:
    - key: workload-class
      value: gpu
      effect: NoSchedule
  containers:
    - name: trainer
      resources:
        limits:
          nvidia.com/gpu: 1
```

## Platform ↔ tenant interactions

- **Capacity growth.** Karpenter provisions new nodes automatically when pending pods carry the right selector and toleration. Tenants do not file a ticket for more capacity within an existing class.
- **New workload class (e.g., GPU).** The platform adds a NodePool + EC2NodeClass, publishes the label / taint contract, and updates the onboarding manual. Tenants adopt it with a spec change.
- **Rescheduling for maintenance.** Karpenter respects PodDisruptionBudgets and per-class disruption budgets. Tenants own their PDBs.

---

## Demos

| Demo            | Class              | Illustrates                                                                                             |
| --------------- | ------------------ | ------------------------------------------------------------------------------------------------------- |
| `nginx-web`     | general            | Simple stateless workload landing on the default class, no toleration.                                  |
| `to-do-app`     | general + database | Full-stack app: web tier on `general`, Postgres on `database` with taint toleration and `gp3-iops` PVC. |
| ML training pod | gpu                | Discussion only — shows the spec shape; not provisioned in the demo cluster.                            |

#### Open items

- **Create a Karpenter `platform` NodePool.** Extends the class elastically for platform components that do not need to run on the bootstrap group. Must carry the same `workload-class=platform` label and `workload-class=platform:NoSchedule` taint as the bootstrap group so the contract is uniform.
- **Add the `platform` toleration to every platform Helm release.** Karpenter, Istio, ArgoCD, cert-manager, ESO, Prometheus stack, Loki, Alloy. Karpenter is the critical-path one — without the toleration, its controller pod stays Pending on the tainted bootstrap group and no elastic capacity is ever provisioned.
- **Enforce placement in admission.** Kyverno should reject tenant workloads that set `nodeSelector.workload-class: platform` — the taint already fences tenants out, but admission gives a clean error at submit time instead of a Pending pod.

---
