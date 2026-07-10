# EKS Platform - ArgoCD Runbook

[Back](../README.md)

- [EKS Platform - ArgoCD Runbook](#eks-platform---argocd-runbook)
  - [ArgoCD - repo layout](#argocd---repo-layout)
  - [Login](#login)
  - [Bootstrap](#bootstrap)
  - [Onboarding a New Application](#onboarding-a-new-application)
  - [Debug](#debug)

---

## ArgoCD - repo layout

```
argocd/
├─ root.yaml       # app-of-apps entry point → renders bootstrap/
├─ bootstrap/      # three child app-of-apps that render projects/, platform/, workloads/
├─ projects/       # AppProject CRs (guardrails: allowed repos, namespaces, resources per team)
├─ platform/       # cluster addons owned by the platform team (ESO, Karpenter, ALBC, Istio, etc.)
└─ workloads/      # user-facing apps owned by dev teams (voting-app, future apps)
```

- ordering: `argocd.argoproj.io/sync-wave` annotations (lower waves sync first). Filenames do not carry ordering.

---

## Login

Required before any admin action. Points kubeconfig at the cluster, exposes the ArgoCD UI locally, and authenticates the `argocd` CLI.

```sh
aws eks update-kubeconfig --region ca-central-1 --name multi-tenant-eks-dev

# open the UI locally
kubectl -n argocd port-forward svc/argocd-server 8080:443

# admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode; echo

# CLI login (once port-forward is running)
argocd login localhost:8080 --username admin --insecure

# list applications / projects
kubectl -n argocd get applications
kubectl -n argocd get appprojects
argocd app list
```

---

## Bootstrap

- One-time setup for a fresh cluster. 
- Applying `root.yaml` triggers the app-of-apps chain: `root` → `bootstrap/` → `projects/` + `platform/` + `workloads/`. 
  - From that point on, Argo self-manages via git.

```sh
aws eks update-kubeconfig --region ca-central-1 --name multi-tenant-eks-dev

# hand control to the root app-of-apps
kubectl apply -f argocd/root.yaml
```

---

## Onboarding a New Application

Platform team lands the guardrail (`AppProject`); dev team lands the workload (`Application`). Two separate PRs, clear ownership.

**Platform team — guardrail PR:**

- Gather requirements from the dev team: app name, namespace, target repo, cluster-scoped resources needed (e.g. `HTTPRoute`), IAM/IRSA needs.
- Add an `AppProject` under `projects/<team>.yaml` scoping `sourceRepos`, `destinations` (namespace), `clusterResourceWhitelist`, and (optional) `roles` for team RBAC.
- Update `CODEOWNERS` so `workloads/<app>/` requires dev-team review.
- Provision any prerequisite infra (IRSA, DNS, RDS) via Terraform.

**Dev team — workload PR:**

- Add the Helm chart or manifests under `helm/<app>/` (or a separate repo).
- Add `workloads/<app>/application.yaml` with `spec.project: <team>` and `spec.destination.namespace: <ns>` matching the `AppProject`.
- Merge to `master` — the `workloads` app-of-apps picks it up automatically.

**Verification:**

- `argocd app list` shows the new app as `Synced` and `Healthy`.
- `argocd app get <app>` shows `Project: <team>` (not `default`) — confirms the guardrail is enforced.

---

## Debug

Common commands for diagnosing and recovering stuck ArgoCD applications.

```sh
# --- inspect ---
kubectl -n argocd get app <name> -o yaml
kubectl -n argocd describe app <name>
argocd app get <name>
argocd app history <name>

# --- force a sync ---
argocd app sync <name>
argocd app sync <name> --prune
argocd app sync <name> --force --replace     # last resort: server-side replace

# --- clear a stuck operation (app shows "operation in progress" forever) ---
kubectl -n argocd patch app/<name> --type merge -p '{"status":{"operationState":null},"operation":null}'
argocd app terminate-op <name>

# --- refresh cache (git out of sync with UI) ---
argocd app get <name> --refresh
argocd app get <name> --hard-refresh

# --- remove finalizer so a stuck app can be deleted ---
kubectl -n argocd patch app/<name> --type merge -p '{"metadata":{"finalizers":[]}}'
kubectl -n argocd delete app <name>


# examples from this repo
kubectl -n argocd patch app/root            --type merge -p '{"metadata":{"finalizers":[]}}'
kubectl -n argocd patch app/platform        --type merge -p '{"metadata":{"finalizers":[]}}'
kubectl -n argocd patch app/eso             --type merge -p '{"metadata":{"finalizers":[]}}'
kubectl -n argocd patch app/karpenter       --type merge -p '{"metadata":{"finalizers":[]}}'
kubectl -n argocd patch app/istio-gateway   --type merge -p '{"metadata":{"finalizers":[]}}'

# clean up
kubectl delete apps --all -n argocd
kubectl get apps -n argocd -o name | xargs -I {} kubectl patch {} -n argocd --type=merge -p '{"metadata":{"finalizers":[]}}'


# --- nuclear: delete without cascading to cluster resources ---
argocd app delete <name> --cascade=false

# --- controller logs ---
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-application-controller --tail=200 -f
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-repo-server --tail=200 -f
```
