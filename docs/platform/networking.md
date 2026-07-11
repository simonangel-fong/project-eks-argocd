# Multi-tenant Platform Runbook - Networking Capability

[Back](../README.md)

- [Overview](#overview)
- [Responsibility Model](#responsibility-model)
- [Tenant Consumption Pattern](#tenant-consumption-pattern)
- [Common Issues and Commands](#common-issues-and-commands)
- [Values that must match Terraform](#values-that-must-match-terraform)

---

## Overview

Tenants ship one `HTTPRoute` and get a routable, TLS-terminated hostname — no AWS, DNS, or cert wiring.

Data path: `client → NLB → shared Istio Gateway → HTTPRoute → tenant Service → ztunnel-encrypted pod`.

| Concern       | Tooling                                                | Key resource                                                              |
| ------------- | ------------------------------------------------------ | ------------------------------------------------------------------------- |
| Ingress       | Gateway API + Istio ambient                            | Shared `Gateway istio-ingress/istio-ingress` (`gatewayClassName: istio`)  |
| Load balancer | AWS Load Balancer Controller (NLB, IP target type)     | Provisioned via `Gateway.spec.infrastructure.annotations`                 |
| TLS           | cert-manager + Let's Encrypt (DNS-01)                  | Wildcard `*.arguswatcher.net` → Secret `arguswatcher-net-wildcard-tls`    |
| DNS           | external-dns → Route 53                                | Reconciled from `HTTPRoute.spec.hostnames`                                |
| East-west     | Istio ambient (ztunnel)                                | mTLS via namespace label `istio.io/dataplane-mode: ambient`               |

Manifests: [argocd/platform/networking/](../../argocd/platform/networking/), [istio-gateway/](../../argocd/platform/networking/istio-gateway/), [cert-manager-resources/](../../argocd/platform/security/cert-manager-resources/).

---

## Responsibility Model

| Concern                                  | Platform | Tenant | Notes                                                                       |
| ---------------------------------------- | :------: | :----: | --------------------------------------------------------------------------- |
| Shared `Gateway`, NLB, wildcard cert     |    ✅    |        | One `Gateway` in `istio-ingress`; NLB and cert are platform-owned.          |
| DNS zone `arguswatcher.net` (Route 53)   |    ✅    |        | external-dns has write access.                                              |
| Subdomain contract `<team>.arguswatcher.net` | ✅    |        | Kyverno rejects `HTTPRoute` hostnames outside the tenant's subdomain.       |
| East-west mTLS                           |    ✅    |        | Namespace label opt-in; zero code change for tenants.                       |
| `HTTPRoute` (routing, hostname, matches) |          |   ✅   | Tenants own routing under their subdomain.                                  |
| NetworkPolicy                            |          |   ✅   | Must allow `169.254.7.127/32` for probes (ambient SNAT).                    |
| Custom (non-`arguswatcher.net`) domain   |    ⚠️    |   ⚠️   | Not in the default contract; needs a platform listener + cert.              |

---

## Tenant Consumption Pattern

Attach to the shared Gateway with an `HTTPRoute`. No Service or ingress annotations.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web
  namespace: team-a
spec:
  parentRefs:
    - name: istio-ingress
      namespace: istio-ingress
  hostnames: [team-a.arguswatcher.net]
  rules:
    - matches: [{ path: { type: PathPrefix, value: / } }]
      backendRefs: [{ name: web, port: 80 }]
```

Ambient mesh opt-in (per namespace, once):

```sh
kubectl label namespace team-a istio.io/dataplane-mode=ambient
```

---

## Common Issues and Commands

```sh
# inventory
kubectl get gateway,httproute -A
kubectl get certificate,order,challenge -A
kubectl -n istio-system get pods                # istiod + ztunnel

# debug a stuck resource
kubectl describe httproute <name> -n <ns>       # Parents / Conditions
kubectl describe gateway istio-ingress -n istio-ingress
kubectl describe certificate arguswatcher-net-wildcard -n istio-ingress

# controller logs
kubectl -n kube-system   logs -l app.kubernetes.io/name=aws-load-balancer-controller --tail=200 -f
kubectl -n cert-manager  logs -l app.kubernetes.io/name=cert-manager                --tail=200 -f
kubectl -n external-dns  logs -l app.kubernetes.io/name=external-dns                --tail=200 -f
kubectl -n istio-system  logs -l app=ztunnel                                        --tail=200 -f
```

| Symptom                                              | Likely cause                                                                    | Fix                                                                              |
| ---------------------------------------------------- | ------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `HTTPRoute` `Accepted: False` (`NotAllowedByListeners`) | Hostname outside `*.arguswatcher.net`, or namespace not allowed                 | Fix the hostname; confirm listener `allowedRoutes`.                              |
| `HTTPRoute` accepted but 404                         | `backendRefs` Service has no endpoints or wrong port                            | `kubectl get endpoints -n <ns>`; check pod readiness and `targetPort`.           |
| Gateway has no `ADDRESS`                             | ALBC not running / missing IAM, **or** cluster/VPC drift (see next section)     | ALBC logs + Pod Identity; confirm `clusterName`/`vpcId` match Terraform.         |
| `503 upstream connect error`                         | Ambient SNAT (`169.254.7.127/32`) blocked by tenant NetworkPolicy               | Allow `169.254.7.127/32` in the tenant's default-deny policy.                    |
| Certificate stuck `Issuing`                          | DNS-01 can't write to Route 53 (cert-manager Pod Identity) or bad ClusterIssuer | Inspect `Order`/`Challenge`; cert-manager logs.                                  |
| DNS record not created                               | Hostname outside managed zone, or external-dns not watching `HTTPRoute`         | Confirm zone; check `--source=gateway-httproute` and logs.                       |
| mTLS not enforced                                    | Namespace missing `istio.io/dataplane-mode=ambient`                             | Label both namespaces; restart pods.                                             |

---

## Values that must match Terraform

Drift here has a wide blast radius: a broken ALBC means **no NLB → no Gateway address → every tenant `HTTPRoute` is unreachable → external-dns writes no records**.

| Where                                                                              | Field                               | Must match                                              |
| ---------------------------------------------------------------------------------- | ----------------------------------- | ------------------------------------------------------- |
| [albc.yaml](../../argocd/platform/networking/albc.yaml)                            | `clusterName`, `vpcId`, `region`    | EKS cluster name, VPC ID (`module.vpc`), cluster region |
| [istio-gateway/gateway.yaml](../../argocd/platform/networking/istio-gateway/gateway.yaml) | `aws-load-balancer-name` annotation | EKS cluster name (used by ALBC for tag discovery)       |

Quick check after any Terraform change:

```sh
terraform -chdir=infra output -raw vpc_id
terraform -chdir=infra output -raw cluster_name
kubectl -n kube-system logs -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50 | grep -Ei "cluster|vpc"
kubectl -n istio-ingress get gateway istio-ingress -o jsonpath='{.status.addresses}'
```
