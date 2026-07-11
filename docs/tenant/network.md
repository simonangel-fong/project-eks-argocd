# Multi-tenant Platform Guide - Network

[Back](../../README.md)

- [Multi-tenant Platform Guide - Network](#multi-tenant-platform-guide---network)
  - [Overview](#overview)
  - [What Tenants Get for Free](#what-tenants-get-for-free)
  - [How to Expose a Service](#how-to-expose-a-service)
  - [Example](#example)
  - [Rules of the Road](#rules-of-the-road)

---

## Overview

The platform ships out-of-the-box ingress, TLS, DNS, and east-west mTLS. A tenant ships one `HTTPRoute` and gets a routable, TLS-terminated hostname — no AWS, DNS, or certificate wiring required.

---

## What Tenants Get for Free

| Capability     | Provided by the platform                                                  |
| -------------- | ------------------------------------------------------------------------- |
| Public URL     | Any hostname under `<team>.arguswatcher.net`                              |
| TLS            | Wildcard `*.arguswatcher.net` — valid cert, auto-renewed                  |
| Load balancer  | Shared internet-facing NLB fronting the cluster                           |
| DNS record     | Created automatically from `HTTPRoute.spec.hostnames`                     |
| East-west mTLS | Automatic between pods in ambient-enabled namespaces (no code changes)    |

---

## How to Expose a Service

Ship one `HTTPRoute` in the tenant namespace, attached to the shared Gateway.

| Field                          | Value                                                              |
| ------------------------------ | ------------------------------------------------------------------ |
| `parentRefs[0].name`           | `istio-ingress`                                                    |
| `parentRefs[0].namespace`      | `istio-ingress`                                                    |
| `hostnames`                    | Any subdomain of `<team>.arguswatcher.net`                         |
| `rules[].backendRefs`          | The tenant's `Service` and port                                    |

No Service annotations, no ingress annotations, no certificate references.

---

## Example

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

DNS, TLS, and load balancing are wired automatically. Verify with:

```sh
curl -I https://team-a.arguswatcher.net    # expect 200/301 and a valid cert
```

---

## Rules of the Road

- **Hostnames stay within `<team>.arguswatcher.net`.** Kyverno rejects any `HTTPRoute` that claims a hostname outside the tenant's subdomain.
- **No custom domains by default.** Bringing a non-`arguswatcher.net` domain requires a platform request (adds a Gateway listener + cert).
- **Ambient mTLS is automatic** — namespaces are labeled `istio.io/dataplane-mode=ambient` at onboarding. No sidecar injection, no pod restarts.
- **NetworkPolicy is tenant-owned.** Default-deny ships with the namespace; additional allow rules are the tenant's responsibility.
- **Health probes need the SNAT allow-rule.** Ambient rewrites kubelet probes to `169.254.7.127/32`. If a tenant adds a stricter NetworkPolicy, it must keep the ingress rule from `169.254.7.127/32`, or probes fail.
- **Route not resolving?** Check `kubectl describe httproute` for `Accepted: False` — usually a hostname outside the subdomain or a `backendRefs` Service with no endpoints.
