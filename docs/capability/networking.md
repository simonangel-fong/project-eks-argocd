# Multi-tenant Cluster Capabilities: Networking

[Back](../README.md)

- [Multi-tenant Cluster Capabilities: Networking](#multi-tenant-cluster-capabilities-networking)
  - [Networking capabilities](#networking-capabilities)
      - [Components in scope](#components-in-scope)
    - [Responsibility model](#responsibility-model)
    - [Design principles](#design-principles)
  - [Team subdomain contract](#team-subdomain-contract)
  - [Tenant consumption pattern](#tenant-consumption-pattern)
  - [Platform ↔ tenant interactions](#platform--tenant-interactions)
  - [Demos](#demos)
  - [Open items](#open-items)

---

## Networking capabilities

**Purpose.** Define how external traffic reaches tenant workloads. Three pieces move together: **ingress** (Gateway API + Istio), **TLS** (cert-manager + Let's Encrypt), and **DNS** (external-dns + Route 53). The design goal is a single opinionated path — a tenant ships one `HTTPRoute` and gets a routable, TLS-terminated hostname without touching AWS, DNS, or certificates.

#### Components in scope

| Concern       | Tooling                                                      | Notes                                                                        |
| ------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------------- |
| Ingress       | Gateway API + Istio ambient (`gatewayClassName: istio`)      | One shared `Gateway` on an internet-facing NLB.                              |
| Load balancer | AWS Load Balancer Controller (NLB, IP target type)           | NLB provisioned by the `Gateway` via infrastructure annotations.             |
| TLS           | cert-manager + Let's Encrypt (`letsencrypt-prod`) via DNS-01 | Wildcard cert for `*.arguswatcher.net`.                                      |
| DNS           | external-dns → Route 53                                      | Tenants declare hostnames on `HTTPRoute`; records are created automatically. |
| East-west     | Istio ambient (ztunnel)                                      | Covered in Phase 03.                                                         |

### Responsibility model

| Concern                                             | Platform | Tenant | Notes                                                                              |
| --------------------------------------------------- | :------: | :----: | ---------------------------------------------------------------------------------- |
| `GatewayClass` and shared `Gateway`                 |    ✅    |        | One `Gateway` in `istio-ingress`, `gatewayClassName: istio`.                       |
| NLB lifecycle and annotations                       |    ✅    |        | Controlled by `Gateway.spec.infrastructure.annotations`.                           |
| DNS zone (`arguswatcher.net`)                       |    ✅    |        | Zone lives in Route 53; external-dns has write access.                             |
| Wildcard TLS certificate                            |    ✅    |        | `*.arguswatcher.net` issued by cert-manager, mounted on the shared `Gateway`.      |
| Team subdomain contract (`<team>.arguswatcher.net`) |    ✅    |        | Kyverno enforces that HTTPRoute hostnames match the tenant's subdomain.            |
| `HTTPRoute` in tenant namespace                     |          |   ✅   | Tenants declare their own routing rules, referencing the shared `Gateway`.         |
| Hostname choice (within their subdomain)            |          |   ✅   | Any hostname under `<team>.arguswatcher.net`.                                      |
| Path / header / method routing                      |          |   ✅   | `HTTPRoute` match rules are entirely tenant-owned.                                 |
| Custom domain (non-`arguswatcher.net`)              |    ⚠️    |   ⚠️   | Out of scope for the default contract; requires platform to add a listener + cert. |

### Design principles

- **One shared Gateway, many `HTTPRoute`s.** Provisioning an NLB per tenant is expensive and slow. A single Gateway with `allowedRoutes.namespaces.from: All` lets any tenant namespace attach without ceremony.
- **TLS is a platform concern, not a tenant concern.** Tenants never handle certificates. The wildcard cert covers every tenant hostname under `arguswatcher.net`.
- **DNS is automatic, but scoped.** external-dns creates records for any `HTTPRoute` hostname, but Kyverno rejects hostnames outside the tenant's subdomain — so a tenant cannot silently hijack another tenant's DNS.
- **Gateway API, not `VirtualService`.** `HTTPRoute` is the tenant-facing surface. Mesh-specific resources (`VirtualService`, `DestinationRule`) remain available for platform use and for tenants who need advanced Istio features, but are not part of the default contract.
- **HTTP is redirected, not served.** The `Gateway` accepts port 80 for the ACME challenge and health checks; production traffic uses 443. Redirect from 80→443 is the tenant's `HTTPRoute` responsibility today; a shared redirect policy on the Gateway is an _Open item_.

## Team subdomain contract

Each tenant gets a subdomain of the form `<team>.arguswatcher.net`. They may claim:

- `<team>.arguswatcher.net` — the apex of their subdomain, or
- `<anything>.<team>.arguswatcher.net` — any depth of sub-subdomain.

This is enforced at admission by the `httproute-hostname-scoped-to-team` Kyverno policy ([kyverno-policies/httproute-hostname-scoped-to-team.yaml](argocd/platform-capabilities/security/kyverno-policies/httproute-hostname-scoped-to-team.yaml)), which reads the namespace's `team` label and compares it against every hostname in the `HTTPRoute`.

## Tenant consumption pattern

Tenants attach to the shared Gateway with an `HTTPRoute`. No `Service` annotations, no ingress annotations, no certificate manipulation.

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
  hostnames:
    - team-a.arguswatcher.net
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: web
          port: 80
```

On admission the platform automatically:

1. Kyverno checks that `team-a.arguswatcher.net` matches the namespace's `team` label.
2. external-dns creates an ALIAS record in Route 53 pointing to the shared NLB.
3. The shared TLS certificate already covers `*.arguswatcher.net`, so HTTPS works immediately with no per-tenant certificate action.

## Platform ↔ tenant interactions

- **Add a hostname under an existing subdomain.** Tenant edits their `HTTPRoute`. No platform action.
- **New tenant subdomain.** Onboarding creates the `team` label and namespace; no DNS delegation change is needed because the whole zone is platform-managed and the wildcard cert already covers the subdomain.
- **Custom domain (`example.com`).** Out of the default contract. Platform must add a listener to the shared `Gateway`, a `Certificate` for the domain, and — if the tenant does not delegate the zone — coordinate DNS with the domain owner.
- **Traffic spike / NLB scaling.** NLBs scale transparently; no tenant or platform action.
- **Gateway maintenance / restart.** Ambient traffic drains via ztunnel; short reconnect windows are the only tenant-visible symptom.

## Demos

| Demo            | Hostname                                                             | Illustrates                                                       |
| --------------- | -------------------------------------------------------------------- | ----------------------------------------------------------------- |
| `nginx-web`     | `team-a.arguswatcher.net`                                            | Minimal `HTTPRoute` on the default team subdomain.                |
| `to-do-app`     | `todo.team-b.arguswatcher.net` (API), `team-b.arguswatcher.net` (UI) | Two hostnames under one subdomain, same `HTTPRoute` or two.       |
| Team C analyzer | `analyzer.team-c.arguswatcher.net`                                   | Ingress not required for the core function; used for a status UI. |

## Open items

- **Shared HTTP→HTTPS redirect.** Today the redirect is per-tenant `HTTPRoute` boilerplate. A single `HTTPRoute` in `istio-ingress` matching every hostname on port 80 with a `RequestRedirect` filter would remove that boilerplate.
- **Rate limiting.** No cluster-level or per-tenant rate limits at the edge. Deferred until abuse is observed.
- **WAF.** No AWS WAF association on the NLB (NLB does not support WAF directly; would require an ALB in front or CloudFront). Out of scope for the default contract.
- **Internal-only routes.** Every hostname today is internet-facing. A second `Gateway` on an internal NLB (with `aws-load-balancer-scheme: internal` and a private ClusterIssuer / self-signed CA) would let tenants expose services to the VPC only.
- **Custom-domain onboarding.** Formalize the process for a tenant to bring their own domain: DNS delegation vs. cert-manager DNS-01 with the tenant's provider vs. platform-owned zone.
- **`allowedRoutes.namespaces.from: All` is permissive.** Combined with the Kyverno subdomain check it is safe, but the belt-and-braces version is a namespace `Selector` matching only namespaces with a `team` label.

---
