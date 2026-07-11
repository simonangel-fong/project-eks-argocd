# Multi-tenant Platform Runbook - ArgoCD

[Back](../README.md)

- [Multi-tenant Platform Runbook - ArgoCD](#multi-tenant-platform-runbook---argocd)
  - [Repo Layout](#repo-layout)
  - [Login](#login)
  - [Bootstrap](#bootstrap)
  - [Debug](#debug)

---

## Repo Layout

App-of-apps hierarchy: `root.yaml` → `bootstrap/` → `projects/` + `platform/` + `tenants/`.

```
argocd/
├── root.yaml                # entry point; points at bootstrap/
├── bootstrap/               # first-level app-of-apps
│   ├── 01-projects.yaml     # syncs projects/
│   ├── 02-platform.yaml     # syncs platform/
│   └── 03-tenants.yaml      # syncs tenants/
├── projects/                # AppProject guardrails (RBAC, allowed repos/destinations)
│   ├── platform.yaml
│   ├── team-a.yaml
│   └── team-b.yaml
├── platform/                # cluster-wide capabilities (managed by platform team)
│   ├── compute/             # karpenter + NodePools/EC2NodeClasses
│   ├── delivery/            # argo-rollouts + AnalysisTemplates
│   ├── networking/          # istio (ambient), ALBC, external-dns, gateway-api CRDs
│   ├── observability/       # kube-prometheus-stack, loki, alloy
│   ├── security/            # cert-manager, ESO, kyverno + policies
│   └── storage/             # gp3 / gp3-iops StorageClasses
└── tenants/                 # per-tenant Application entries
    ├── team-a.yaml
    └── team-b.yaml
```

---

## Login

Points kubeconfig at the cluster, port-forwards the UI, and logs the CLI in.

```sh
aws eks update-kubeconfig --region ca-central-1 --name multi-tenant-eks-dev

# UI: https://localhost:8080
kubectl -n argocd port-forward svc/argocd-server 8080:443

# initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode; echo

# CLI login (with port-forward running)
argocd login localhost:8080 --username admin --insecure

# inspect
kubectl -n argocd get applications,appprojects
argocd app list
```

---

## Bootstrap

One-time setup for a fresh cluster. Applying `root.yaml` triggers the app-of-apps chain; from that point, ArgoCD self-manages via git.

Before applying, fill in these placeholders in the platform charts:

| Chart     | Field                    | Value                            |
| --------- | ------------------------ | -------------------------------- |
| Karpenter | `clusterName`            | `<eks_cluster_name>`             |
| Karpenter | `interruptionQueue`      | `<karpenter_queue_name>`         |
| Karpenter | `EC2NodeClass.role`      | `<karpenter_node_role_name>`     |
| ALBC      | `clusterName`, `vpcId`   | `<eks_cluster_name>`, `<vpc_id>` |
| Gateway   | `aws-load-balancer-name` | `<eks_cluster_name>`             |

Then apply:

```sh
aws eks update-kubeconfig --region ca-central-1 --name multi-tenant-eks-dev
kubectl apply -f argocd/root.yaml
```

Verify:

```sh
argocd app list
# every app should reach Synced + Healthy; platform apps first, then tenants
```

---

## Debug

```sh
# inspect
kubectl -n argocd get app <name> -o yaml
argocd app get <name>
argocd app history <name>

# force sync
argocd app sync <name>
argocd app sync <name> --prune
argocd app sync <name> --force --replace     # last resort: server-side replace

# clear a stuck operation ("operation in progress" forever)
kubectl -n argocd patch app/<name> --type merge \
  -p '{"status":{"operationState":null},"operation":null}'
argocd app terminate-op <name>

# refresh cache (git out of sync with UI)
argocd app get <name> --refresh
argocd app get <name> --hard-refresh

# remove finalizer so a stuck app can be deleted
kubectl -n argocd patch app/<name> --type merge \
  -p '{"metadata":{"finalizers":[]}}'
kubectl -n argocd delete app <name>

# bulk: clear finalizers + delete all apps
kubectl -n argocd get apps -o name \
  | xargs -I {} kubectl -n argocd patch {} --type merge \
      -p '{"metadata":{"finalizers":[]}}'
kubectl -n argocd delete apps --all

# nuclear: delete app without cascading to cluster resources
argocd app delete <name> --cascade=false

# controller logs
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-application-controller --tail=200 -f
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-repo-server           --tail=200 -f
```
