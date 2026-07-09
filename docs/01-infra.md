# EKS Platform - Infra

[Back](../README.md)

- [EKS Platform - Infra](#eks-platform---infra)
  - [aws design](#aws-design)
  - [terraform](#terraform)
  - [Development](#development)

---

## aws design

traffic: `api-gateway (HTTP API) → vpc link → private ALB → EKS (Gateway API)`

- network
  - vpc: `10.0.0.0/16`, region `ca-central-1`, az `a` + `b`

---

- eks
  - version: 1.35
  - node group: managed, `t3.large` × 2, on-demand
  - auth: EKS Pod Identity

- add-ons (managed):
  - `vpc-cni`,
  - `coredns`,
  - `kube-proxy`
  - `aws-ebs-csi-driver` — postgres PVC
  - `metrics-server` — HPA
  - `aws-gateway-api-controller` — matches `values-prod.yaml` `className: aws-alb`

- storage:
  - `gp3` StorageClass,
  - default, `WaitForFirstConsumer`, `allowVolumeExpansion: true`

---

## terraform

- remote state:
  - S3 (SSE + `use_lockfile = true`, no DynamoDB)
- layout — numbered by layer (bootstrap → foundation → cluster → edge):

```
infra/
│  ├─ 01-variables.tf
│  ├─ 02-locals.tf
│  ├─ 03-providers.tf      # tf + provider version pins live here
│  ├─ 04-outputs.tf
│  ├─ 10-vpc.tf        # foundation: network
│  ├─ 11-eks.tf        # cluster: control plane + node group + add-ons
│  ├─ 12-eks-argocd.tf        # argocd
│  ├─ 13-eks-eso.tf
│  ├─ 1-eks-eso.tf
```

---

## Development

```sh
terraform -chdir=infra init -backend-config=backend.hcl -upgrade
terraform -chdir=infra fmt && terraform -chdir=infra validate
terraform -chdir=infra plan

terraform -chdir=infra apply -auto-approve
terraform -chdir=infra refresh
terraform -chdir=infra output


terraform -chdir=infra destroy -auto-approve
```

- Connect cluster

```sh
aws eks update-kubeconfig --region ca-central-1 --name voting-dev
# Added new context arn:aws:eks:ca-central-1:099139718958:cluster/voting-dev to /home/ubuntuadmin/.kube/config

k get node
# NAME                                           STATUS   ROLES    AGE     VERSION
# ip-10-0-12-95.ca-central-1.compute.internal    Ready    <none>   2m48s   v1.36.2-eks-7d6f6ec
# ip-10-0-15-157.ca-central-1.compute.internal   Ready    <none>   2m48s   v1.36.2-eks-7d6f6ec
# ip-10-0-16-76.ca-central-1.compute.internal    Ready    <none>   2m47s   v1.36.2-eks-7d6f6ec
```
