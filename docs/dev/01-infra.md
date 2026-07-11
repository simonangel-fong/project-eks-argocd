# Multi-tenant Platform Runbook - Infrastructure

[Back](../README.md)

- [Multi-tenant Platform Runbook - Infrastructure](#multi-tenant-platform-runbook---infrastructure)
  - [AWS Design](#aws-design)
  - [Terraform](#terraform)
  - [Development](#development)

---

## AWS Design

Traffic flow: `API Gateway (HTTP API) → VPC Link → private ALB → EKS (Gateway API)`

- **Network**
  - VPC: `10.0.0.0/16`, region `ca-central-1`, AZs `a` + `b`
  - Public subnets tagged `kubernetes.io/role/elb=1` for internet-facing ALBs
  - Private subnets tagged `karpenter.sh/discovery=<cluster>` for node autoscaling

- **EKS**
  - Version: `1.36`
  - Bootstrap node group: managed, `t3.xlarge` × 2, on-demand
    - reserves bootstrap nodes for the platform stack (`CoreDNS`, `Karpenter`, `ArgoCD`);
    - Taint `workload-class=platform:NoSchedule`;
    - tenant workloads run on Karpenter-provisioned nodes
  - Auth: EKS Pod Identity (no IRSA / OIDC federation)

- **Cluster add-ons** (managed)
  - `vpc-cni` — network policy enabled
  - `coredns`, `kube-proxy`
  - `eks-pod-identity-agent`
  - `metrics-server` — HPA
  - `aws-ebs-csi-driver` — Postgres PVCs (installed by `13-eks-csi.tf`, not the base module)

- **Storage**
  - `gp3` StorageClass — default, `WaitForFirstConsumer`, `allowVolumeExpansion: true`

---

## Terraform

- **Remote state:** S3 with SSE and `use_lockfile = true` (no DynamoDB).
- **Layout:**

```
infra/
├── 01-variables.tf
├── 02-locals.tf           # cluster name, versions, namespaces
├── 03-providers.tf
├── 04-outputs.tf
├── 10-vpc.tf
├── 11-eks.tf              # cluster + bootstrap node group + managed add-ons
├── 12-eks-karpenter.tf
├── 13-eks-csi.tf          # EBS CSI driver + Pod Identity
├── 14-eks-argocd.tf       # ArgoCD Helm release
├── 15-eks-eso.tf          # External Secrets Operator
├── 16-eks-albc.tf         # AWS Load Balancer Controller
└── backend.hcl
```

---

## Development

Run Terraform from the repo root; `-chdir=infra` keeps state and lockfile scoped to `infra/`.

```sh
terraform -chdir=infra init -backend-config=backend.hcl -upgrade
terraform -chdir=infra fmt && terraform -chdir=infra validate
terraform -chdir=infra plan

terraform -chdir=infra apply -auto-approve
terraform -chdir=infra refresh
terraform -chdir=infra output

terraform -chdir=infra destroy -auto-approve
```

Connect to the cluster:

```sh
aws eks update-kubeconfig --region ca-central-1 --name multi-tenant-eks-dev

kubectl get nodes
# NAME                                           STATUS   ROLES    AGE     VERSION
# ip-10-0-12-95.ca-central-1.compute.internal    Ready    <none>   2m48s   v1.36.2-eks-7d6f6ec
# ip-10-0-15-157.ca-central-1.compute.internal   Ready    <none>   2m48s   v1.36.2-eks-7d6f6ec
```
