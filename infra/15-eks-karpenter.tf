# ################################################################################
# Karpenter — controller IAM role, node IAM role, SQS interruption queue,
# EventBridge rules, access entry, Pod Identity association.
#
# Helm chart is installed by Argo CD (argocd/apps/karpenter.yaml); this file
# only creates the AWS-side plumbing the chart needs.
# ################################################################################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = module.eks.cluster_name

  namespace       = local.karpenter_namespace
  service_account = local.karpenter_service_account

  # Node role name is referenced by EC2NodeClass in phase 7.7 — keep it stable.
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${local.common_name}-karpenter-node"

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  create_pod_identity_association = true
  enable_spot_termination         = true

  # Standard IAM policies cap at 6,144 chars; Karpenter's controller policy
  # exceeds that. Inline policies allow up to 10,240 chars.
  enable_inline_policy = true
}
