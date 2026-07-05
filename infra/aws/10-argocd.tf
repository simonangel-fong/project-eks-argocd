# locals {
#   # IAM Identity Center home region (verified via `aws sso-admin list-instances`)
#   idc_region = "us-east-1"
# }

# # ################################################################################
# # AWS Identity Center lookups
# # ################################################################################
# data "aws_ssoadmin_instances" "this" {
#   provider = aws.identity # region: us-east-1
# }

# data "aws_identitystore_group" "aws_administrator" {
#   provider          = aws.identity # region: us-east-1
#   identity_store_id = one(data.aws_ssoadmin_instances.this.identity_store_ids)

#   alternate_identifier {
#     unique_attribute {
#       attribute_path  = "DisplayName"
#       attribute_value = "AWSAdministrator"
#     }
#   }
# }

# # ################################################################################
# # EKS Capability Module: ArgoCD
# # ################################################################################
# module "argocd_eks_capability" {
#   source  = "terraform-aws-modules/eks/aws//modules/capability"
#   version = "21.15.1"

#   type         = "ARGOCD"
#   name         = "argocd"
#   cluster_name = module.eks.cluster_name

#   configuration = {
#     argo_cd = {
#       aws_idc = {
#         idc_instance_arn = one(data.aws_ssoadmin_instances.this.arns)
#         idc_region       = local.idc_region
#       }
#       namespace = "argocd"
#       rbac_role_mapping = [{
#         role = "ADMIN"
#         identity = [{
#           id   = data.aws_identitystore_group.aws_administrator.group_id
#           type = "SSO_GROUP"
#         }]
#       }]
#     }
#   }

#   # IAM Role/Policy
#   iam_policy_statements = {
#     ECRRead = {
#       actions = [
#         "ecr:GetAuthorizationToken",
#         "ecr:BatchCheckLayerAvailability",
#         "ecr:GetDownloadUrlForLayer",
#         "ecr:BatchGetImage",
#       ]
#       resources = ["*"]
#     }
#   }

#   tags = local.default_tags
# }

# ################################################################################
# # ArgoCD (Helm)
# ################################################################################



# ##############################
# Argo CD
# ##############################
resource "helm_release" "argocd" {
  name       = local.argocd_release
  repository = local.argocd_repo
  chart      = local.argocd_chart
  version    = local.argocd_chart_ver
  namespace  = local.argocd_namespace

  create_namespace = true

  values = compact([
    local.argocd_values
  ])

  atomic        = false
  wait          = false
  wait_for_jobs = false
  timeout       = 600
}
