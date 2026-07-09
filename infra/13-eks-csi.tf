# eks-csi.tf

# Creates Amazon EKS Pod Identity roles.
module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name                      = "${local.common_name}-csi-pod-role"
  attach_aws_ebs_csi_policy = true
}

# install addon
resource "aws_eks_addon" "csi" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_update = "PRESERVE"
  pod_identity_association {
    role_arn        = module.ebs_csi_pod_identity.iam_role_arn
    service_account = local.eks_csi_service_account
  }
}
