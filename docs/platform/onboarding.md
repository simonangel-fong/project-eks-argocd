# Multi-tenant Platform Runbook - Tenant Onboarding

[Back](../../README.md)

- [Multi-tenant Platform Runbook - Tenant Onboarding](#multi-tenant-platform-runbook---tenant-onboarding)
  - [Overview](#overview)
  - [Intake](#intake)
  - [Onboarding Steps](#onboarding-steps)
  - [Tenant Bootstrap Manifest](#tenant-bootstrap-manifest)
  - [Verification](#verification)
  - [Common Issues](#common-issues)

---

## Overview

Onboarding is one platform-side PR that lands three artifacts:

1. **Namespace + guardrails** — namespace, `PeerAuthentication`, `NetworkPolicy` (default-deny + platform-ingress allow), `ResourceQuota`, `LimitRange`.
2. **ArgoCD `AppProject`** — RBAC boundary: allowed source repos and destination namespace.
3. **ArgoCD `Application`** — watches the tenant's manifest path in git.

Everything after is self-service via the tenant's repo. Reference: [argocd/projects/team-a.yaml](../../argocd/projects/team-a.yaml), [argocd/tenants/team-a.yaml](../../argocd/tenants/team-a.yaml).

---

## Intake

Collect from the tenant before opening the PR:

| Field                | Example                                                 | Used for                              |
| -------------------- | ------------------------------------------------------- | ------------------------------------- |
| Team name (`<team>`) | `team-a`                                                | namespace, subdomain, `team` label    |
| Source repo          | `https://github.com/simonangel-fong/project-eks-argocd` | `AppProject.sourceRepos`              |
| Manifests path       | `demo-app/team-a`                                       | `Application.spec.source.path`        |
| Cluster-scoped needs | e.g. `HTTPRoute` (Gateway API)                          | `AppProject.clusterResourceWhitelist` |
| Quota tier           | baseline / custom                                       | `ResourceQuota` values                |
| AWS access?          | which secrets / S3 buckets                              | Pod Identity role provisioning        |

---

## Onboarding Steps

1. **Open a PR** on this repo adding two files:
   - `argocd/projects/<team>.yaml` — `AppProject`
   - `argocd/tenants/<team>.yaml` — namespace + guardrails + `Application` (single manifest, `---` separated; see [Tenant Bootstrap Manifest](#tenant-bootstrap-manifest))
2. **Provision AWS prerequisites** (if requested) via Terraform: Pod Identity role, ASM secret paths, S3 buckets.
3. **Update `CODEOWNERS`** so `demo-app/<team>/` (or the tenant's manifest path) requires the dev team's review.
4. **Merge to `master`.** The `bootstrap/03-tenants.yaml` app-of-apps picks the new file up automatically.
5. **Confirm sync** — see [Verification](#verification).

The tenant then opens their own PR against their manifests path (Deployment/StatefulSet, Service, HTTPRoute, PVC). See [../tenant/onboarding.md](../tenant/onboarding.md) for the tenant-facing flow.

---

## Tenant Bootstrap Manifest

`argocd/tenants/<team>.yaml` bundles the namespace guardrails and the `Application` in one file (mirrors [argocd/tenants/team-a.yaml](../../argocd/tenants/team-a.yaml)). Key blocks:

**1. Namespace — ambient mesh enrollment + team label**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: <team>
  labels:
    team: <team>
    istio.io/dataplane-mode: ambient # ztunnel takes over; no sidecars
```

**2. `PeerAuthentication` — refuse plaintext peers**

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata: { name: default, namespace: <team> }
spec:
  mtls: { mode: STRICT }
```

**3. NetworkPolicy — default-deny + platform-ingress allow**

Ships as two policies: a blanket `default-deny` and a companion `allow-platform-ingress-and-dns` that restores the paths the platform needs. **Every rule matters** — omitting one breaks day-one traffic:

| Rule                               | Why                                                                                     |
| ---------------------------------- | --------------------------------------------------------------------------------------- |
| Ingress from `istio-ingress` ns    | Shared Gateway → tenant pods                                                            |
| Ingress from `istio-system` ns     | ztunnel / waypoint HBONE                                                                |
| Ingress from `169.254.7.127/32`    | **Ambient SNATs kubelet probes to this link-local** — without this, all probes time out |
| Ingress from `10.0.0.0/16`         | Non-ambient probe path (fallback if a pod exits ambient)                                |
| Ingress on TCP 15008 from any ns   | HBONE — east-west ambient mTLS tunnel                                                   |
| Egress UDP/TCP 53 → `kube-system`  | DNS                                                                                     |
| Egress to `istio-system`           | ztunnel xDS + upstream to waypoints                                                     |
| Egress to any pod in the namespace | Internal traffic                                                                        |

**4. Baseline `ResourceQuota` + `LimitRange`**

Defaults from [team-a.yaml](../../argocd/tenants/team-a.yaml):

| Field                     | Value            |
| ------------------------- | ---------------- |
| `requests.cpu`            | `4`              |
| `requests.memory`         | `8Gi`            |
| `limits.cpu`              | `8`              |
| `limits.memory`           | `16Gi`           |
| `persistentvolumeclaims`  | `10`             |
| Container default request | `100m` / `128Mi` |
| Container default limit   | `500m` / `512Mi` |

**5. ArgoCD `Application`**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <team>
  namespace: argocd
  labels: { scope: tenant, team: <team> }
spec:
  project: <team>
  source:
    repoURL: <tenant_repo>
    targetRevision: master
    path: <tenant_manifest_path>
  destination:
    server: https://kubernetes.default.svc
    namespace: <team>
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [ServerSideApply=true]
```

---

## Verification

```sh
# 1. AppProject + Application exist and are healthy
argocd app get <team>
kubectl -n argocd get appproject <team>

# 2. Namespace guardrails applied
kubectl get ns <team> --show-labels                    # team=<team>, istio.io/dataplane-mode=ambient
kubectl -n <team> get peerauthentication,networkpolicy,resourcequota,limitrange

# 3. Ambient mesh has picked up the namespace
istioctl ztunnel-config workloads | grep <team>

# 4. Tenant workload smoke test (after tenant PR merges)
kubectl -n <team> get pods,svc,httproute
curl -I https://<team>.arguswatcher.net                # expect 200/301, valid TLS cert
```

---

## Common Issues

| Symptom                                                               | Likely cause                                                             | Fix                                                                                                |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- |
| Tenant `Application` stuck `Unknown`                                  | `AppProject` `sourceRepos` or `destinations` don't match the Application | Align repo URL and namespace between `AppProject` and `Application`.                               |
| Kyverno rejects tenant workloads (`require-team-label`, etc.)         | Manifests missing `team` label, requests, probes, or use `:latest`       | Point the tenant at the Kyverno policy list ([06-security.md](06-security.md#kyverno-policy-set)). |
| All pods time out on probes right after onboarding                    | NetworkPolicy missing the `169.254.7.127/32` ambient-SNAT rule           | Re-apply `allow-platform-ingress-and-dns` from the reference manifest.                             |
| East-west traffic silently dropped between two ambient namespaces     | HBONE (TCP 15008) not allowed in tenant NetworkPolicy                    | Add the `port: 15008` ingress rule.                                                                |
| Tenant hits quota on first deploy                                     | Baseline quota too tight for the workload                                | Bump `ResourceQuota` in the tenant file after capacity review.                                     |
| `HTTPRoute` rejected by Kyverno (`httproute-hostname-scoped-to-team`) | Hostname not under `<team>.arguswatcher.net`                             | Tenant must use their subdomain, or platform adds a custom listener + cert.                        |
