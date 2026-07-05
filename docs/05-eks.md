# EKS (phase 6)

goal

- private eks cluster + add-ons
- terraform-managed, remote state
- argocd capability

---

## aws design

traffic: `api-gateway (HTTP API) → vpc link → private ALB → EKS (Gateway API)`

skip for now: cognito, s3 static hosting, cloudfront

---

## network

- vpc: `10.0.0.0/16`, region `ca-central-1`, az `a` + `b`
- private subnets only (workloads + ALB)
- egress: NAT gateway (simple) — swap for VPC endpoints later (ecr.api, ecr.dkr, s3, sts, logs) to cut cost
- postgres StatefulSet pinned to one AZ (EBS is zonal)

---

## eks

- version: 1.33 (latest supported)
- node group: managed, `t3.large` × 3, on-demand
  - `t3.medium` too tight once postgres (1Gi/4Gi) + app + system pods land
- auth: EKS Pod Identity (not IRSA)

add-ons (managed):

- `vpc-cni`, `coredns`, `kube-proxy`
- `aws-ebs-csi-driver` — postgres PVC
- `metrics-server` — HPA
- `aws-gateway-api-controller` — matches `values-prod.yaml` `className: aws-alb`

storage: `gp3` StorageClass, default, `WaitForFirstConsumer`, `allowVolumeExpansion: true`

argocd capability: cluster is prepared for argocd (namespace + prerequisites); the actual install + `Application` manifests are phase 7.

---

## terraform

remote state: S3 (SSE + `use_lockfile = true`, no DynamoDB)

layout — numbered by layer (bootstrap → foundation → cluster → edge):

```
infra/
├─ aws/
│  ├─ 01-variables.tf
│  ├─ 02-locals.tf
│  ├─ 03-providers.tf      # tf + provider version pins live here
│  ├─ 04-outputs.tf
│  ├─ 05-aws-vpc.tf        # foundation: network
│  ├─ 06-aws-eks.tf        # cluster: control plane + node group + add-ons
│  ├─ 07-aws-api-gateway.tf # edge: http api
│  └─ 08-aws-vpc-link.tf   # edge: api gw → private alb
└─ modules/
   ├─ vpc/   # wraps terraform-aws-modules/vpc/aws
   └─ eks/   # wraps terraform-aws-modules/eks/aws
```

backend (s3 + native locking) lives in a separate `backend.tf` at repo root or inside `03-providers.tf` — it isn't a layer, just bootstrap.

---

## provisioning phases

| phase | description                                                               |
| ----- | ------------------------------------------------------------------------- |
| 1     | bootstrap: variables, locals, providers, outputs (`01`–`04`)              |
| 2     | foundation: VPC, subnets, NAT, routes (`05-aws-vpc.tf`)                   |
| 3     | cluster: EKS control plane, node group, managed add-ons (`06-aws-eks.tf`) |
| 4     | edge: API Gateway (`07`) + VPC Link to private ALB (`08`)                 |

---

## done when

- `terraform apply` clean, no drift on re-plan
- `aws eks describe-cluster` → `ACTIVE`
- managed add-ons all `ACTIVE`
- API Gateway invoke URL reaches the private ALB through VPC Link (test target = ALB default 404 is fine — no workloads yet)

---

## Development

```sh
terraform -chdir=infra/aws init -backend-config=backend.hcl
terraform -chdir=infra/aws fmt && terraform -chdir=infra/aws validate
terraform -chdir=infra/aws plan

terraform -chdir=infra/aws apply -auto-approve
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
