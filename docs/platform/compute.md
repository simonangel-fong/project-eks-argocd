# Multi-tenant Platform Runbook - Compute Capability

[Back](../../README.md)

- [Multi-tenant Platform Runbook - Compute Capability](#multi-tenant-platform-runbook---compute-capability)
  - [Overview](#overview)
  - [Implementation](#implementation)
  - [Node Classification](#node-classification)
  - [Responsibility Model](#responsibility-model)
  - [Tenant Consumption Pattern](#tenant-consumption-pattern)
  - [Common Issues and Commands](#common-issues-and-commands)
    - [Values that must match Terraform](#values-that-must-match-terraform)

---

## Overview

The platform ships out-of-the-box compute autoscaling via **Karpenter**. Tenants request compute by workload class; the platform owns instance-type selection, capacity mix, and lifecycle.

---

## Implementation

1. **Enable Karpenter in AWS** — SQS interruption queue, IAM roles for the controller and nodes, subnet/SG discovery tags ([infra/12-eks-karpenter.tf](../../infra/12-eks-karpenter.tf)).
2. **Install the Karpenter controller** as a platform Application ([argocd/platform/compute/karpenter.yaml](../../argocd/platform/compute/karpenter.yaml)).
3. **Publish `NodePool` + `EC2NodeClass` per workload class** ([argocd/platform/compute/karpenter-nodes/](../../argocd/platform/compute/karpenter-nodes/)).

---

## Node Classification

- Workload classes are identified by the label `workload-class=<class>`.
- Tainted classes require a matching toleration; tenants never reference instance families or sizes.

| Class      | Label                     | Provisioned by                     | Taint                                | Capacity         | Instance selection           | Purpose                                                          |
| ---------- | ------------------------- | ---------------------------------- | ------------------------------------ | ---------------- | ---------------------------- | ---------------------------------------------------------------- |
| `platform` | `workload-class=platform` | EKS managed node group + Karpenter | `workload-class=platform:NoSchedule` | on-demand        | `t3.xlarge` (bootstrap), `m` | Bootstraps the cluster; runs Karpenter, Istio, ArgoCD, ESO, etc. |
| `general`  | `workload-class=general`  | Karpenter                          | none                                 | on-demand + spot | families `t`,`m`; gen > 3    | Default class for stateless tenant workloads.                    |
| `database` | `workload-class=database` | Karpenter                          | `workload-class=database:NoSchedule` | on-demand only   | families `m`,`r`; gen > 5    | Stateful tenant workloads: databases, queues, caches with PVCs.  |
| `gpu`      | `workload-class=gpu`      | Karpenter                          | `workload-class=gpu:NoSchedule`      | on-demand only   | families `g5`,`g6`           | GPU-backed tenant workloads (inference, training).               |

The `platform` class is deliberately hybrid:

- **EKS managed node group** provides the always-on capacity Karpenter itself needs to run. Tainted to prevent general workloads; add-ons like `coredns` and `metrics-server` carry the matching toleration.
- **Karpenter `platform` NodePool** scales the class for the remaining platform components.

**NodePool limits** (guardrails against runaway scale):

| NodePool   | CPU limit | Extra limit         | Disruption policy                  |
| ---------- | --------- | ------------------- | ---------------------------------- |
| `general`  | 100       | —                   | `WhenEmptyOrUnderutilized`, `30s`  |
| `database` | 32        | —                   | `WhenEmpty`, `5m`, budget `1 node` |
| `gpu`      | 64        | `nvidia.com/gpu: 4` | `WhenEmpty`, `5m`, budget `1 node` |

All NodePools set `expireAfter: 720h` — nodes recycle every 30 days for AMI patching.

---

## Responsibility Model

| Concern                                       | Platform | Tenant | Notes                                                                        |
| --------------------------------------------- | :------: | :----: | ---------------------------------------------------------------------------- |
| Cluster and NodePool definitions              |    ✅    |        | Terraform manages EKS; `NodePool` + `EC2NodeClass` are GitOps-managed.       |
| Node autoscaling and consolidation            |    ✅    |        | Karpenter reconciles to pending pod demand.                                  |
| Node lifecycle (AMI, patching, expiry)        |    ✅    |        | `expireAfter: 720h` forces monthly recycling; AMI pinned to `al2023@latest`. |
| Workload-class contract (labels + taints)     |    ✅    |        | Stable across releases; documented in the onboarding manual.                 |
| Pod spec, resource requests / limits          |          |   ✅   | Tenants declare what they need; platform admits or rejects via Kyverno.      |
| Placement hints (`nodeSelector`, tolerations) |          |   ✅   | Tenants opt into a workload class; they never name instance types.           |
| HPA / KEDA scaling rules                      |          |   ✅   | Tenants own scaling behavior; platform ships `metrics-server`.               |

---

## Tenant Consumption Pattern

Tenants combine a `nodeSelector` with a matching `toleration` (only required for tainted classes). They never reference instance families, sizes, or capacity types directly.

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
# gpu — nodeSelector + toleration + gpu resource request
spec:
  nodeSelector:
    workload-class: gpu
  tolerations:
    - key: workload-class
      value: gpu
      effect: NoSchedule
  containers:
    - name: app
      resources:
        limits:
          nvidia.com/gpu: 1
```

---

## Common Issues and Commands

```sh
# --- inventory ---
kubectl get nodepool
kubectl get ec2nodeclass
kubectl get nodeclaim                     # in-flight and provisioned nodes
kubectl get nodes -L workload-class,karpenter.sh/nodepool,node.kubernetes.io/instance-type

# --- inspect a stuck NodePool / NodeClaim ---
kubectl describe nodepool <name>
kubectl describe nodeclaim <name>          # look at Conditions + Events
kubectl get events -A --field-selector reason=FailedScheduling

# --- pending pods: why did Karpenter not launch a node? ---
kubectl -n kube-system logs -l app.kubernetes.io/name=karpenter --tail=200 -f \
  | grep -i "<pod-name>\|nodeclaim\|unschedulable"

# --- force node recycle (planned maintenance / AMI bump) ---
kubectl delete nodeclaim <name>            # Karpenter drains + replaces
kubectl taint node <node> karpenter.sh/disrupted=true:NoSchedule

# --- drain a node ---
kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
```

**Common issues**

| Symptom                                      | Likely cause                                                               | Fix                                                                                          |
| -------------------------------------------- | -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Pod stays `Pending`, no NodeClaim created    | `nodeSelector` value has no matching NodePool, or missing toleration       | Verify `workload-class` label + toleration match a NodePool in `kubectl get nodepool`.       |
| NodeClaim stuck in `Launching`               | Subnet / SG discovery tags missing, or IAM role can't launch the instance  | Check `EC2NodeClass` selectors and controller logs for AWS API errors.                       |
| Nodes never consolidate                      | Pods block eviction (PDB at `minAvailable: 100%`, `do-not-disrupt` annot.) | Relax PDB or remove `karpenter.sh/do-not-disrupt` annotation.                                |
| CPU limit hit (`limits.cpu` on the NodePool) | Tenant scaled beyond the class budget                                      | Raise the NodePool `limits.cpu` after capacity review, or push the tenant to a bigger class. |
| Karpenter controller `CrashLoopBackOff` or nodes never provision on a fresh cluster | Chart values drifted from Terraform outputs — cluster name, SQS queue, or node IAM role name in the ArgoCD manifests don't match what Terraform actually created | Re-align the platform manifests with `terraform -chdir=infra output`; see [Values that must match Terraform](#values-that-must-match-terraform) below. |

### Values that must match Terraform

Several fields in the compute Applications are hardcoded and must equal the resources provisioned by [infra/12-eks-karpenter.tf](../../infra/12-eks-karpenter.tf). Mismatches surface as controller crashes, `NodeClaim` launch failures, or pods stuck `Pending` with no NodeClaim.

| Where                                                     | Field                                                                        | Must match                                    |
| --------------------------------------------------------- | ---------------------------------------------------------------------------- | --------------------------------------------- |
| `argocd/platform/compute/karpenter.yaml` (Helm values)    | `settings.clusterName`                                                       | EKS cluster name (`multi-tenant-eks-dev`)     |
| `argocd/platform/compute/karpenter.yaml` (Helm values)    | `settings.interruptionQueue`                                                 | SQS queue (`Karpenter-multi-tenant-eks-dev`)  |
| `argocd/platform/compute/karpenter.yaml` (Helm values)    | `nodeSelector.karpenter.sh/controller: "true"`                               | Label present on the bootstrap node group     |
| `argocd/platform/compute/karpenter-nodes/*-ec2nodeclass.yaml` | `spec.role`                                                                  | Karpenter node IAM role (`multi-tenant-eks-dev-karpenter-node`) |
| `argocd/platform/compute/karpenter-nodes/*-ec2nodeclass.yaml` | `subnetSelectorTerms` / `securityGroupSelectorTerms` tag `karpenter.sh/discovery` | EKS cluster name                              |

Quick check after any Terraform change:

```sh
terraform -chdir=infra output -raw karpenter_queue_name
terraform -chdir=infra output -raw karpenter_node_iam_role_name
kubectl -n kube-system logs -l app.kubernetes.io/name=karpenter --tail=50 \
  | grep -Ei "cluster name|queue|role"    # controller reports the values it loaded
```
