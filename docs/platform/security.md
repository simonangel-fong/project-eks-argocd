# Multi-tenant Platform Runbook - Security Capability

[Back](../../README.md)

- [Multi-tenant Platform Runbook - Security Capability](#multi-tenant-platform-runbook---security-capability)
  - [Overview](#overview)
  - [Responsibility Model](#responsibility-model)
  - [Isolation Model](#isolation-model)
  - [Kyverno Policy Set](#kyverno-policy-set)
  - [Tenant Consumption Pattern](#tenant-consumption-pattern)
  - [Common Issues and Commands](#common-issues-and-commands)

---

## Overview

The platform ships secrets vending, workload identity, admission control, and mesh mTLS as one contract. Tenants declare intent (`ExternalSecret`, `ServiceAccount`, `NetworkPolicy`); the platform enforces the guardrails.

| Concern           | Tooling                                           | Enforcement point                    |
| ----------------- | ------------------------------------------------- | ------------------------------------ |
| Sensitive data    | External Secrets Operator + AWS Secrets Manager   | Runtime (`ExternalSecret` reconcile) |
| Workload identity | EKS Pod Identity                                  | Runtime (SDK credential vending)     |
| TLS certificates  | cert-manager + Let's Encrypt (`letsencrypt-prod`) | Runtime (Certificate reconcile)      |
| mTLS (east-west)  | Istio ambient (ztunnel)                           | Data plane                           |
| Admission policy  | Kyverno `ClusterPolicy`                           | Admission (API-server webhook)       |
| Network policy    | VPC CNI NetworkPolicy + Istio AuthorizationPolicy | Data plane                           |
| Resource fairness | `ResourceQuota` + `LimitRange`                    | Admission                            |

Manifests: [argocd/platform/security/](../../argocd/platform/security/) — ESO ([eso-resources/](../../argocd/platform/security/eso-resources/)), cert-manager ([cert-manager-resources/](../../argocd/platform/security/cert-manager-resources/)), Kyverno ([kyverno-policies/](../../argocd/platform/security/kyverno-policies/)).

---

## Responsibility Model

| Concern                                                   | Platform | Tenant | Notes                                                               |
| --------------------------------------------------------- | :------: | :----: | ------------------------------------------------------------------- |
| Namespace + `team=<name>` label                           |    ✅    |        | Drives Kyverno matching, cost allocation, alert routing.            |
| Default-deny NetworkPolicy, `ResourceQuota`, `LimitRange` |    ✅    |        | Applied at namespace creation.                                      |
| `ClusterSecretStore` (AWS Secrets Manager)                |    ✅    |        | Single store `aws-secretsmanager`; tenants create `ExternalSecret`. |
| Pod Identity role for tenant workloads                    |    ✅    |        | Created per tenant on request.                                      |
| Kyverno `ClusterPolicy` set                               |    ✅    |        | Cluster-wide; tenants cannot bypass or edit.                        |
| Ambient enrollment (namespace label)                      |    ✅    |        | `istio.io/dataplane-mode=ambient` at onboarding.                    |
| `ExternalSecret` + secret values in ASM                   |          |   ✅   | Tenants own secret material; platform owns the vending path.        |
| `ServiceAccount` → workload wiring                        |          |   ✅   | Tenants set `spec.serviceAccountName`.                              |
| Additional NetworkPolicy / AuthorizationPolicy            |          |   ✅   | Tenants layer allow-rules on top of default-deny.                   |
| Pod-level `securityContext`                               |          |   ✅   | Non-root, drop caps, seccomp — Kyverno enforces baseline.           |

---

## Isolation Model

| Layer        | Mechanism                                      | What it stops                                                          |
| ------------ | ---------------------------------------------- | ---------------------------------------------------------------------- |
| Namespace    | Kubernetes RBAC                                | Tenant A cannot `get/list/patch` Tenant B's objects.                   |
| Network (L3) | NetworkPolicy — default deny + selective allow | Tenant A pods cannot open TCP/UDP to Tenant B pods.                    |
| Network (L4) | Istio ambient + `PeerAuthentication: STRICT`   | On-cluster attacker cannot read pod-to-pod traffic; plaintext refused. |
| Resources    | `ResourceQuota` + `LimitRange`                 | Tenant A cannot starve Tenant B on CPU / memory / PVC storage.         |

---

## Kyverno Policy Set

Every policy excludes platform namespaces (`kube-system`, `karpenter`, `istio-system`, `argocd`, `cert-manager`, `external-secrets`, `monitoring`) and applies to tenant namespaces only. Source: [argocd/platform/security/kyverno-policies/](../../argocd/platform/security/kyverno-policies/).

| Policy                              | Enforces                                                                             |
| ----------------------------------- | ------------------------------------------------------------------------------------ |
| `require-team-label`                | Every workload carries a `team` label — drives alerting, cost allocation, ownership. |
| `require-requests`                  | Every container declares CPU and memory `requests`.                                  |
| `require-probes`                    | Every container declares liveness and readiness probes.                              |
| `require-runbook-annotation`        | Every workload has a runbook URL annotation.                                         |
| `disallow-latest-tag`               | No `image: foo:latest`.                                                              |
| `disallow-privileged`               | No privileged containers, no host mounts of `/`.                                     |
| `disallow-host-namespace`           | No `hostNetwork`, `hostPID`, `hostIPC`.                                              |
| `restrict-image-registries`         | Images must come from the approved registry list.                                    |
| `httproute-hostname-scoped-to-team` | Tenants may only claim hostnames under their own subdomain.                          |

---

## Tenant Consumption Pattern

**Vend a secret from AWS Secrets Manager:**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-creds
  namespace: team-a
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretsmanager
    kind: ClusterSecretStore
  target:
    name: db-creds # k8s Secret created in team-a
  data:
    - secretKey: password
      remoteRef: { key: team-a/db, property: password }
```

**Consume an AWS API with Pod Identity** (role provisioned by platform):

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: worker
  namespace: team-a
---
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      serviceAccountName: worker # Pod Identity association wires role via serviceAccount
```

---

## Common Issues and Commands

```sh
# inventory
kubectl get clustersecretstore
kubectl get externalsecret -A
kubectl get clusterpolicy
kubectl get policyreport,clusterpolicyreport -A
kubectl get resourcequota,limitrange -A

# debug a stuck ExternalSecret
kubectl describe externalsecret <name> -n <ns>       # Conditions show ASM error
kubectl -n external-secrets logs -l app.kubernetes.io/name=external-secrets --tail=200 -f

# debug admission rejection
kubectl -n kyverno logs -l app.kubernetes.io/name=kyverno --tail=200 -f
kubectl get events -n <ns> --field-selector reason=PolicyViolation

# check Pod Identity vending
kubectl -n <ns> exec <pod> -- aws sts get-caller-identity
```

| Symptom                                             | Likely cause                                                                        | Fix                                                                                     |
| --------------------------------------------------- | ----------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `ExternalSecret` shows `SecretSyncedError`          | Secret path wrong in ASM, or ESO Pod Identity lacks `secretsmanager:GetSecretValue` | `describe externalsecret`; verify ASM key + ESO Pod Identity role policy.               |
| `kubectl apply` rejected with Kyverno message       | Manifest violates a `ClusterPolicy` (missing label, `:latest`, no probes, etc.)     | Fix the manifest; policy name is in the rejection message.                              |
| Pod can't reach AWS API (`NoCredentialProviders`)   | Missing Pod Identity association for the `ServiceAccount`                           | Ask platform to create the association; verify with `aws sts get-caller-identity`.      |
| Tenant pods can't reach each other after ambient on | Missing/strict NetworkPolicy, or ambient SNAT (`169.254.7.127/32`) blocked          | Allow `169.254.7.127/32` and the peer pod selector in the tenant's default-deny policy. |
| `ResourceQuota exceeded` on deploy                  | Tenant consumed the namespace quota                                                 | Right-size requests, or request a quota increase (platform PR).                         |
| Certificate not renewing                            | cert-manager Pod Identity lost `route53:ChangeResourceRecordSets`                   | Check cert-manager logs and the `letsencrypt-prod` ClusterIssuer.                       |
