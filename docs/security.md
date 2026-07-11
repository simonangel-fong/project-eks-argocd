# Multi-tenant Cluster Capabilities: Security

[Back](../README.md)

- [Multi-tenant Cluster Capabilities: Security](#multi-tenant-cluster-capabilities-security)
  - [Storage capabilities](#storage-capabilities)
    - [Phase 03 — Security capabilities](#phase-03--security-capabilities)
      - [Components in scope](#components-in-scope)
      - [Responsibility model](#responsibility-model)
      - [Isolation model](#isolation-model)
      - [Admission-time contract (Kyverno)](#admission-time-contract-kyverno)
      - [Secrets — consumption pattern](#secrets--consumption-pattern)
      - [mTLS — consumption pattern](#mtls--consumption-pattern)
      - [Onboarding contract](#onboarding-contract)
      - [Platform ↔ tenant interactions](#platform--tenant-interactions)
      - [Open items](#open-items)

---

## Storage capabilities

### Phase 03 — Security capabilities

**Purpose.** Define the security contract between the platform and tenants. Two layers matter: **isolation** — what stops one tenant from affecting another — and **enforcement** — what stops a tenant from violating the platform's assumptions in the first place. Both are non-negotiable for a multi-tenant cluster.

#### Components in scope

| Concern           | Tooling                                           | Enforcement point                         |
| ----------------- | ------------------------------------------------- | ----------------------------------------- |
| Sensitive data    | External Secrets Operator + AWS Secrets Manager   | Runtime (`ExternalSecret` reconciliation) |
| Workload identity | EKS Pod Identity                                  | Runtime (SDK credential vending)          |
| TLS certificates  | cert-manager + Let's Encrypt `ClusterIssuer`      | Runtime (Certificate reconciliation)      |
| mTLS (east-west)  | Istio ambient (ztunnel)                           | Runtime (data plane)                      |
| Admission policy  | Kyverno `ClusterPolicy`                           | Admission (API server webhook)            |
| Network policy    | VPC CNI NetworkPolicy + Istio AuthorizationPolicy | Data plane                                |
| Resource fairness | `ResourceQuota` + `LimitRange`                    | Admission                                 |

#### Responsibility model

| Concern                                        | Platform | Tenant | Notes                                                                         |
| ---------------------------------------------- | :------: | :----: | ----------------------------------------------------------------------------- |
| Namespace creation and labels                  |    ✅    |        | Namespace carries a `team=<name>` label used by Kyverno and observability.    |
| Default-deny NetworkPolicy                     |    ✅    |        | Applied at namespace creation; tenants layer allow-rules on top.              |
| Additional NetworkPolicy / AuthorizationPolicy |          |   ✅   | Tenants own their internal ingress / egress rules.                            |
| `ResourceQuota` and `LimitRange`               |    ✅    |        | Baseline quota per namespace; tenants request increases.                      |
| `ClusterSecretStore` (AWS Secrets Manager)     |    ✅    |        | One `ClusterSecretStore`; tenants create `ExternalSecret` in their namespace. |
| Secret values in AWS Secrets Manager           |          |   ✅   | Tenants own their secret material; platform owns the vending path.            |
| Pod Identity role for tenant workloads         |    ✅    |        | Created per tenant on request (same pattern as Phase 02 S3 access).           |
| `ServiceAccount` → workload wiring             |          |   ✅   | Tenants set `spec.serviceAccountName`.                                        |
| Kyverno `ClusterPolicy` set                    |    ✅    |        | Cluster-wide; tenants cannot bypass or edit.                                  |
| Istio ambient enrollment (namespace label)     |    ⚠️    |        | Deferred — kubelet probe interaction requires Waypoint proxy; see "Ambient experiment". |
| Pod-level `securityContext`                    |          |   ✅   | Tenants set non-root, drop capabilities, seccomp — Kyverno enforces baseline. |

#### Isolation model

Three layers today, each enforced by a different mechanism. Any one alone is insufficient; together they form the tenant boundary.

| Layer        | Mechanism                                      | What it stops                                                                     |
| ------------ | ---------------------------------------------- | --------------------------------------------------------------------------------- |
| Namespace    | Kubernetes namespace + RBAC                    | Tenant A cannot `get / list / patch` Tenant B's objects.                          |
| Network (L3) | NetworkPolicy — default deny + selective allow | Tenant A pods cannot open TCP/UDP to Tenant B pods.                               |
| Resources   | `ResourceQuota` + `LimitRange`                 | Tenant A cannot consume so much CPU / memory / PVC storage that Tenant B starves. |

An L7 identity layer (Istio ambient + `AuthorizationPolicy`) is deferred — see "Ambient experiment" below.

Design principles:

- **Default deny, explicit allow.** Every NetworkPolicy is default-deny at namespace creation. Tenants add allow-rules for the ingress paths they need.
- **L3 is the current isolation boundary.** IP/port-based NetworkPolicy stops cross-tenant traffic today. Identity-based L7 policy is on the roadmap; the shift will replace the L3 layer, not stack on top of it.
- **Kyverno is the last line of defense.** If a Kyverno policy would fail closed and break the cluster, that is a signal the policy is too broad — but it is not a reason to loosen the tenant contract.

#### Ambient experiment — what we learned

Both tenant namespaces were briefly labeled `istio.io/dataplane-mode=ambient` to enroll them in Istio ambient mesh. The experiment was reverted; ambient stays off until a Waypoint proxy pattern is in place.

**Findings:**

- Ambient enrollment works end-to-end. Istio CNI on the node picks up the label change, marks pods for interception, and ztunnel starts capturing their traffic.
- Pod-to-pod traffic **inside** an ambient namespace continues to work — verified by `todo-db → todo-web` on port 8080.
- Kubelet HTTP probes against ambient-enrolled pods **fail with connection timeouts**. Probes originate from the node's host network; ztunnel intercepts them but has no matching mTLS session, so packets are dropped.
- This is not a probe-declaration bug. Container ports are named (`http`), probes reference the name, Postgres uses exec probes. The named-port + probe-exemption path that works in Istio sidecar mode does not apply here — ambient has no per-pod proxy to do the probe rewriting.

**Why L7 identity is deferred:**

1. Ambient alone is wire encryption, not access control. You still need `AuthorizationPolicy` to enforce "Team A cannot call Team B" — and today NetworkPolicy already covers that at L3.
2. Making ambient work with kubelet probes requires deploying a **Waypoint proxy** per namespace (L7 gateway) or switching to exec-based probes. Both are non-trivial commitments.
3. The concrete threat model — cross-tenant service calls that need identity-based authz — does not exist yet. Two tenants, no cross-tenant dependencies.

**When to revisit:**

- A tenant onboards that needs to call another tenant's service (requires identity-based `AuthorizationPolicy`).
- Threat model expands to include on-cluster passive attackers (requires wire encryption).
- Compliance requirement forces mTLS between all workloads.

At that point the work is: deploy Waypoint proxies, re-enable ambient enrollment at onboarding, ship `AuthorizationPolicy` as part of the onboarding contract, and remove the NetworkPolicy layer once identity-based rules replace it.

#### Admission-time contract (Kyverno)

The cluster ships a starter set of `ClusterPolicy` objects at [argocd/platform-capabilities/security/kyverno-policies/](argocd/platform-capabilities/security/kyverno-policies/). Every policy excludes platform namespaces (`kube-system`, `karpenter`, `istio-system`, `argocd`, etc.) so it applies to tenant namespaces only.

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

Follow-on policies scheduled below in _Open items_.

#### Secrets — consumption pattern

Tenants never handle raw AWS credentials or embed secret material in Git. The pattern is:

1. Platform ships a single `ClusterSecretStore` (`aws-secretsmanager`) pointing at AWS Secrets Manager in `ca-central-1`.
2. Tenant creates a secret in AWS Secrets Manager (via Terraform, console, or CLI) under a tenant-scoped prefix.
3. Tenant declares an `ExternalSecret` in their namespace referencing the secret name.
4. ESO reconciles the `ExternalSecret` into a native `Secret` in the tenant namespace, which the pod mounts as usual.

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-password
  namespace: team-b
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: aws-secretsmanager
  target:
    name: db-password # native Secret created here
  data:
    - secretKey: password
      remoteRef:
        key: team-b/db/password
```

Access control at the AWS side is enforced by the `ClusterSecretStore`'s IAM role — its policy restricts `secretsmanager:GetSecretValue` to secrets under specific prefixes. A tenant cannot read another tenant's secrets even if they know the ARN.

#### mTLS — consumption pattern (deferred)

_Ambient is currently disabled; see "Ambient experiment" above. When re-enabled with Waypoint support:_

- Namespaces will be labeled `istio.io/dataplane-mode=ambient` at onboarding, with a Waypoint proxy deployed for the namespace to handle kubelet probes and L7 policy.
- All pod-to-pod traffic within the mesh is transparently encrypted by ztunnel — no sidecar, no code change.
- Workload identity is expressed as a SPIFFE ID derived from the ServiceAccount.
- Tenants that want L7 policy (e.g., "only ServiceAccount X can call this Service") declare `AuthorizationPolicy` in their namespace.

#### Onboarding contract

When a tenant onboards, the platform performs the following in a single ArgoCD `ApplicationSet` reconciliation (target state — today parts are still manual):

1. Create namespace `<team>` with label `team=<team>`. Ambient enrollment (`istio.io/dataplane-mode=ambient`) is deferred; see "Ambient experiment".
2. Apply default-deny `NetworkPolicy` (ingress and egress).
3. Apply baseline `ResourceQuota` and `LimitRange`.
4. Create the tenant's `ServiceAccount`(s) and any Pod Identity associations declared in the onboarding request.
5. Register the tenant's `Application` under `argocd/tenants/<team>/`.
6. Provision the tenant's Grafana folder and `PrometheusRule` label scope (Phase 05).

The tenant then owns everything inside that namespace: pods, services, PVCs, `HTTPRoute`s (scoped to their subdomain), `AuthorizationPolicy`, additional NetworkPolicy rules, and `ExternalSecret`s.

#### Platform ↔ tenant interactions

- **Quota increase.** Tenant opens a change request with justification. Platform patches the `ResourceQuota`; no restart required.
- **New AWS secret.** Tenant creates the secret in AWS Secrets Manager under their prefix and declares an `ExternalSecret`. No platform action if the prefix is already allow-listed.
- **New pod-to-pod policy.** Tenant declares NetworkPolicy / AuthorizationPolicy in their namespace. Platform does not review.
- **Cross-tenant call (rare).** Explicitly out of scope for the default contract. Requires platform review and a documented `AuthorizationPolicy` from both sides.

#### Open items

- **Onboarding automation.** Today namespace, quota, default-deny NP, and ArgoCD registration are partly manual. Target: a single `TeamNamespace` Helm chart driven by an `ApplicationSet` — one commit onboards a tenant.
- **Enforce `workload-class: platform` is tenant-forbidden.** Kyverno rule blocking tenant workloads from selecting the platform node class (called out in Phase 01).
- **Enforce explicit `storageClassName` on PVCs.** Called out in Phase 02.
- **Secret prefix contract.** Formalize the AWS Secrets Manager naming convention (`<team>/<component>/<key>`) and align the `ClusterSecretStore` role's IAM policy to those prefixes.
- **Namespace exclusion list is duplicated across every Kyverno policy** (9 places today). Extract to a shared ConfigMap / policy variable.
- **Baseline `PodSecurityContext` policy.** Add Kyverno rules to require `runAsNonRoot`, `readOnlyRootFilesystem` where feasible, and `capabilities.drop: [ALL]`.
- **Egress control.** Today NetworkPolicy handles ingress well; egress to the internet is unrestricted. Deferred; revisit when a tenant handles regulated data.

---
