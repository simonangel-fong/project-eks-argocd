# Multi-tenant Cluster Capabilities: Storage

[Back](../README.md)

- [Multi-tenant Cluster Capabilities: Storage](#multi-tenant-cluster-capabilities-storage)
  - [Storage capabilities](#storage-capabilities)
    - [Responsibility model](#responsibility-model)
    - [Block storage — StorageClass matrix](#block-storage--storageclass-matrix)
  - [Object storage (S3) — access pattern](#object-storage-s3--access-pattern)
  - [Tenant consumption pattern](#tenant-consumption-pattern)
  - [Platform ↔ tenant interactions](#platform--tenant-interactions)
      - [Demos](#demos)
      - [Open items](#open-items)

---

## Storage capabilities

**Purpose.** Define the storage contract between the platform and tenants for two distinct concerns: **block storage** (per-pod PVCs backed by EBS) and **object storage** (tenant-owned S3 buckets accessed by pods). The two share nothing operationally — different providers, different consumption patterns, different failure modes — so they are modeled separately.

### Responsibility model

| Concern                                                | Platform | Tenant | Notes                                                                                                                                |
| ------------------------------------------------------ | :------: | :----: | ------------------------------------------------------------------------------------------------------------------------------------ |
| CSI driver lifecycle                                   |    ✅    |        | `aws-ebs-csi-driver` installed as an EKS-managed add-on with Pod Identity.                                                           |
| StorageClass definitions                               |    ✅    |        | `gp3` (default) and `gp3-iops`, GitOps-managed under [argocd/platform-capabilities/storage/](argocd/platform-capabilities/storage/). |
| PVC creation, sizing, mounting                         |          |   ✅   | Tenants declare PVCs with a `storageClassName` and access mode.                                                                      |
| Volume expansion                                       |          |   ✅   | Enabled at the StorageClass level; tenants patch PVC `spec.resources` themselves.                                                    |
| S3 bucket provisioning                                 |    ✅    |        | Buckets are Terraform-managed alongside the cluster (see Loki bucket precedent in [infra/16-eks-loki.tf](infra/16-eks-loki.tf)).     |
| S3 bucket contents (objects, prefixes)                 |          |   ✅   | Tenants own everything inside the bucket.                                                                                            |
| Pod → S3 identity (IAM role, Pod Identity association) |    ✅    |        | Platform creates the role and binds it to the tenant's ServiceAccount.                                                               |
| ServiceAccount → pod wiring                            |          |   ✅   | Tenants set `spec.serviceAccountName` on their workload.                                                                             |

### Block storage — StorageClass matrix

| Class             | Provisioner       | Type | IOPS / Throughput       | Reclaim  | Binding                | Expansion | Use                                                                                               |
| ----------------- | ----------------- | ---- | ----------------------- | -------- | ---------------------- | --------- | ------------------------------------------------------------------------------------------------- |
| `gp3` _(default)_ | `ebs.csi.aws.com` | gp3  | AWS defaults            | `Delete` | `WaitForFirstConsumer` | ✅        | Default PVC path for stateless caches, scratch space, general-purpose stateful workloads.         |
| `gp3-iops`        | `ebs.csi.aws.com` | gp3  | 10 000 IOPS / 500 MiB/s | `Retain` | `WaitForFirstConsumer` | ✅        | Databases, WALs, write-heavy stateful workloads. `Retain` protects data on accidental PVC delete. |

Design principles:

- **Storage class is a tenant choice, not a workload class inheritance.** A pod on the `database` node class does not automatically get `gp3-iops`; the tenant declares it. Coupling the two would prevent legitimate combinations (e.g., a database that only needs `gp3`, or a stateless workload on `general` that wants provisioned IOPS).
- **`WaitForFirstConsumer` on both classes.** The volume is provisioned in the same AZ as the pod that will mount it, avoiding cross-AZ scheduling failures.
- **`Retain` on `gp3-iops` is a safety net, not a backup strategy.** Orphaned volumes must be cleaned up manually. Backup (Velero, EBS snapshots) is a Phase 05 / roadmap item.
- **No RWX today.** EFS is called out as optional in Phase 00 and will be added only when a tenant requires shared filesystem access.

## Object storage (S3) — access pattern

S3 access is granted via **EKS Pod Identity**, the same mechanism already in production for the Loki bucket ([infra/16-eks-loki.tf](infra/16-eks-loki.tf)). The pattern is:

1. Platform provisions the bucket in Terraform (SSE enabled, public access blocked, lifecycle rules if applicable).
2. Platform creates an IAM role scoped to that bucket ARN with least-privilege actions.
3. Platform creates a `PodIdentityAssociation` binding the role to a `(namespace, serviceAccountName)` pair the tenant will use.
4. Tenant creates the `ServiceAccount` in their namespace and references it in their pod spec.

No static AWS credentials are ever mounted into a tenant pod. Credentials are vended by the Pod Identity Agent at runtime and rotate automatically.

## Tenant consumption pattern

**Block storage — default class:**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cache
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Gi
  # storageClassName omitted → gp3 (default)
```

**Block storage — high-IOPS class:**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: gp3-iops
  resources:
    requests:
      storage: 100Gi
```

**S3 access via Pod Identity:**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: log-analyzer
  namespace: team-c
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: log-analyzer
  namespace: team-c
spec:
  template:
    spec:
      serviceAccountName: log-analyzer # bound to the tenant's IAM role
      containers:
        - name: app
          image: ghcr.io/team-c/log-analyzer:1.0.0
          env:
            - name: BUCKET
              value: team-c-logs-dev
```

## Platform ↔ tenant interactions

- **New bucket request.** Tenant opens a change request naming the bucket, access pattern (read-only / read-write), and target ServiceAccount. Platform applies a Terraform change adding the bucket + role + Pod Identity association. Tenant references the ServiceAccount on next deploy.
- **Bucket policy changes.** Owned by the platform. Tenants do not modify IAM policies inline.
- **PVC growth.** Tenants patch `spec.resources.requests.storage`; the CSI driver expands the underlying volume. No platform action required.
- **Data protection (target state).** Backup and snapshot policies are deferred; called out in Phase 00 as optional.

#### Demos

| Demo                | Storage used               | Illustrates                                                           |
| ------------------- | -------------------------- | --------------------------------------------------------------------- |
| `nginx-web`         | none                       | Stateless workload; no PVC, no bucket.                                |
| `to-do-app`         | `gp3-iops` PVC (Postgres)  | High-IOPS block storage on the `database` node class.                 |
| Team C log analyzer | S3 (read) via Pod Identity | Tenant-owned bucket, IAM role scoped to that bucket, no static creds. |

#### Open items

- **Bucket naming and tagging convention.** Needs to be codified before onboarding a second S3-using tenant, so buckets are consistently named, tagged with tenant / environment, and discoverable.
- **Templating the S3 wiring.** Bucket + IAM role + Pod Identity association is currently hand-written per tenant (see the Loki precedent). A Terraform module or ArgoCD `ApplicationSet` template would keep the onboarding process short.
- **Kyverno policy for PVC hygiene.** Enforce that every PVC declares an explicit `storageClassName` (avoids silent reliance on the default) and a size limit ceiling per namespace.
- **EFS.** Deferred until a shared-filesystem tenant lands.

---
