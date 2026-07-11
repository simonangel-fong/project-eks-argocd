# Multi-tenant Platform Runbook - Storage Capability

[Back](../../README.md)

- [Multi-tenant Platform Runbook - Storage Capability](#multi-tenant-platform-runbook---storage-capability)
  - [Overview](#overview)
  - [Implementation](#implementation)
  - [Responsibility Model](#responsibility-model)
  - [Block Storage — StorageClass Matrix](#block-storage--storageclass-matrix)
  - [Tenant Consumption Pattern](#tenant-consumption-pattern)
  - [Common Issues and Commands](#common-issues-and-commands)

---

## Overview

The platform ships out-of-the-box block storage via the **AWS EBS CSI driver**. Tenants request storage by `storageClassName`; the platform owns the driver, IAM, and StorageClass parameters.

---

## Implementation

1. **Install the CSI driver** as an EKS-managed add-on with Pod Identity ([infra/13-eks-csi.tf](../../infra/13-eks-csi.tf)).
2. **Publish StorageClasses** via GitOps ([argocd/platform/storage/](../../argocd/platform/storage/)):
   - `gp3.yaml` — default class
   - `gp3-iops.yaml` — high-IOPS class for stateful workloads

---

## Responsibility Model

| Concern                        | Platform | Tenant | Notes                                                                                              |
| ------------------------------ | :------: | :----: | -------------------------------------------------------------------------------------------------- |
| CSI driver lifecycle           |    ✅    |        | `aws-ebs-csi-driver` installed as an EKS-managed add-on with Pod Identity.                         |
| StorageClass definitions       |    ✅    |        | `gp3` (default) and `gp3-iops`, GitOps-managed under `argocd/platform/storage/`.                   |
| PVC creation, sizing, mounting |          |   ✅   | Tenants declare PVCs with a `storageClassName` and access mode.                                    |
| Volume expansion               |          |   ✅   | Enabled at the StorageClass level; tenants patch PVC `spec.resources.requests.storage`.            |
| Backup / snapshot policy       |          |   ✅   | Tenants own their `VolumeSnapshot` schedule; platform ships the CSI snapshotter only if requested. |

---

## Block Storage — StorageClass Matrix

| Class             | Provisioner       | Type | IOPS / Throughput               | Reclaim  | Binding                | Expansion | Use                                                                                               |
| ----------------- | ----------------- | ---- | ------------------------------- | -------- | ---------------------- | :-------: | ------------------------------------------------------------------------------------------------- |
| `gp3` _(default)_ | `ebs.csi.aws.com` | gp3  | AWS defaults (3000 / 125 MiB/s) | `Delete` | `WaitForFirstConsumer` |    ✅     | Stateless caches, scratch space, general-purpose stateful workloads.                              |
| `gp3-iops`        | `ebs.csi.aws.com` | gp3  | 10 000 IOPS / 500 MiB/s         | `Retain` | `WaitForFirstConsumer` |    ✅     | Databases, WALs, write-heavy stateful workloads. `Retain` protects data on accidental PVC delete. |

**Notes:**

- `WaitForFirstConsumer` defers volume creation until the pod is scheduled, so the EBS volume lands in the pod's AZ.
- `Retain` on `gp3-iops` means deleting the PVC leaves the underlying volume in AWS — platform must reclaim it manually (`kubectl delete pv` + `aws ec2 delete-volume`).
- EBS volumes are AZ-scoped and `ReadWriteOnce` only. Multi-AZ or `ReadWriteMany` workloads need EFS (not currently offered).

---

## Tenant Consumption Pattern

**Default class (gp3):**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cache
spec:
  accessModes: [ReadWriteOnce]
  # storageClassName omitted → gp3 (default)
  resources:
    requests:
      storage: 10Gi
```

**High-IOPS class (gp3-iops):**

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

**Expand a volume** (tenant self-service, StorageClass has `allowVolumeExpansion: true`):

```sh
kubectl patch pvc postgres-data \
  -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'
# pod must be restarted for the filesystem to grow
```

---

## Common Issues and Commands

```sh
# --- inventory ---
kubectl get storageclass
kubectl get pv,pvc -A
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-ebs-csi-driver

# --- inspect a stuck PVC ---
kubectl describe pvc <name> -n <ns>            # Events show provisioner errors
kubectl get events -n <ns> --field-selector involvedObject.name=<pvc>

# --- CSI driver logs (controller + node) ---
kubectl -n kube-system logs -l app=ebs-csi-controller -c ebs-plugin --tail=200 -f
kubectl -n kube-system logs -l app=ebs-csi-node       -c ebs-plugin --tail=200 -f

# --- release a Released PV so its EBS volume can be reused ---
kubectl patch pv <name> -p '{"spec":{"claimRef":null}}'

# --- manually reclaim a Retained volume ---
kubectl delete pv <name>
aws ec2 delete-volume --volume-id <vol-id>
```

**Common issues**

| Symptom                                                         | Likely cause                                                                                        | Fix                                                                                           |
| --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| PVC stays `Pending`                                             | `WaitForFirstConsumer` — no pod yet consumes it                                                     | Schedule a pod referencing the PVC; check `kubectl describe pvc` if it stays pending after.   |
| PVC `Pending` with `failed to provision volume`                 | CSI controller lacks EBS permissions (Pod Identity broken) or wrong `storageClassName`              | Check controller logs and the `ebs-csi-controller-sa` Pod Identity association.               |
| Pod stuck `ContainerCreating` with `AttachVolume.Attach failed` | Volume in a different AZ than the node (rare with `WaitForFirstConsumer` — usually pre-existing PV) | Delete and recreate the PVC, or move the pod to the volume's AZ.                              |
| `Volume node affinity conflict`                                 | Pod rescheduled to another AZ; EBS volume is AZ-scoped                                              | Add `topology.kubernetes.io/zone` node affinity, or use a StatefulSet with stable scheduling. |
| PVC deleted but EBS volume remains + billed                     | StorageClass `reclaimPolicy: Retain` (expected for `gp3-iops`)                                      | Manually delete the PV, then `aws ec2 delete-volume`.                                         |
| Volume expansion doesn't take effect                            | Filesystem not resized inside the pod                                                               | Restart the pod; the CSI node plugin resizes the FS on remount.                               |
