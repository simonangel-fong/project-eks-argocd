# eks-karpenter.tf

# ##############################
# Karpenter
# ##############################
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = module.eks.cluster_name

  namespace       = local.karpenter_namespace
  service_account = local.karpenter_service_account

  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${local.common_name}-karpenter-node"

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  create_pod_identity_association = true
  enable_spot_termination         = true

  enable_inline_policy = true
}
