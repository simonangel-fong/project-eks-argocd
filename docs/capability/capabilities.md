# Platform capability catalog

What the platform provides, who consumes it, and what's deferred.

## How to read this

Every capability is delivered at **Tier 2 depth** — end-to-end working,
integrated with the tenancy model, documented ownership, roadmap gaps
named. Deeper items are deferred, not hidden.

## Capabilities

| Layer         | Capability                          | Tools                                         | Consumed via                                            |
| ------------- | ----------------------------------- | --------------------------------------------- | ------------------------------------------------------- |
| Compute       | Node autoscaling with workload classes | Karpenter (`general`, `database` NodePools) | `nodeSelector: workload-class: <class>`                 |
| Storage       | Block storage with IOPS tiers       | EBS CSI                                       | `storageClassName: gp3` or `gp3-iops`                   |
| Network       | Service mesh                        | Istio ambient (ztunnel, no sidecars)          | Namespace label `istio.io/dataplane-mode: ambient`      |
| Network       | Ingress + TLS + DNS                 | Gateway API, cert-manager, external-dns       | `HTTPRoute` referencing `istio-ingress/istio-ingress`   |
| Security      | Workload identity                   | ESO + Pod Identity                            | `ExternalSecret` in team namespace                      |
| Security      | Policy enforcement                  | Kyverno (9 starter ClusterPolicies)           | Automatic — admission-time validation                   |
| Security      | Network isolation                   | Kubernetes NetworkPolicy + Istio AuthZ        | Default-deny at namespace creation                      |
| Delivery      | GitOps                              | ArgoCD (self-managing)                        | `Application` under `argocd/tenants/<team>/`            |
| Delivery      | Progressive delivery                | Argo Rollouts + Gateway API plugin            | `Rollout` referencing `ClusterAnalysisTemplate`         |
| Observability | Metrics + dashboards                | Prometheus + Grafana                          | `ServiceMonitor` + team-labeled dashboard ConfigMaps    |
| Observability | Logs                                | Loki + Grafana Alloy DaemonSet                | Automatic — stdout tailed and labeled by team           |
| Observability | Alerting                            | Alertmanager → Slack                          | `PrometheusRule` with `team=<team>` label               |
| Tenancy       | Team onboarding primitive           | TeamNamespace pattern (Helm + ArgoCD)         | See `onboarding.md`                                     |

## Ownership

Everything above is **platform team**–owned: the capability, its lifecycle,
its integration surface, and the on-call for the capability itself.

**Workload teams** own the code that consumes these capabilities — their
apps, dashboards, alerts, SLOs, and on-call for their services.

## Reference implementations shipped by the platform

To establish patterns, the platform ships one of each:

- **PrometheusRule** at [platform-alerts.yaml](../argocd/platform/prometheus-stack-resources/platform-alerts.yaml) — shows the required label/annotation shape teams follow.
- **Grafana dashboard** at [platform-overview-dashboard.yaml](../argocd/platform/prometheus-stack-resources/platform-overview-dashboard.yaml) — shows the ConfigMap-as-dashboard pattern with `grafana_folder` annotation.
- **ClusterAnalysisTemplates** under [argo-rollouts-resources/](../argocd/platform/argo-rollouts-resources/) — reusable canary analysis specs.

Teams copy these patterns; platform doesn't build per-team versions.

## Roadmap

Deferred capabilities. Called out here so absence reads as scope, not oversight.

**Reliability**
- SLO framework (Sloth / Pyrra) — currently, SLO definitions live inline in `PrometheusRule` annotations
- Long-term metrics storage (Thanos / Mimir) — Prometheus retains 7d
- Distributed tracing (Tempo) — Istio ambient emits trace-ready metrics, no collector deployed
- Backup / DR (Velero) — no automated PVC or etcd backup

**Governance**
- SSO for platform tools (ArgoCD, Grafana) via GitHub OAuth, then IAM Identity Center
- Cost visibility (OpenCost) integrated with team labels
- Image signing enforcement via Cosign + Kyverno verify-images policies

**Platform**
- GPU workload class (Karpenter `g5`/`g6`)
- EFS CSI for shared filesystem access
- Cluster-per-environment (covered in separate project)
- Volume snapshot policy for stateful workloads
- Extract platform-namespace exclusion list to shared ConfigMap (currently duplicated across 9 Kyverno policies)

## Non-goals

Explicit exclusions — worth naming so scope is defensible:

- **Data platform** (managed Postgres, Redis, Kafka) — apps run their own or use RDS via Terraform
- **Multi-cluster / multi-region** — one cluster; docs point to separate project for the cluster-per-env story
- **Backstage / IDP portal** — capability catalog lives in docs, not a UI
- **Chaos engineering** — high effort, tangential to core platform story
