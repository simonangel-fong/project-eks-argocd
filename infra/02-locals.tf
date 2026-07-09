# locals.tf

locals {
  # ##############################
  # metadata
  # ##############################
  common_name = "${var.project}-${var.env}"
  region      = "ca-central-1"
  default_tags = {
    Project     = var.project
    Environment = var.env
    ManagedBy   = "terraform"
  }

  # ##############################
  # VPC
  # ##############################
  subnet_azs = ["ca-central-1a", "ca-central-1b"]
  vpc_cidr   = "10.0.0.0/16"

  # ##############################
  # EKS
  # ##############################
  eks_name              = local.common_name
  eks_version           = "1.36"
  eks_node_name         = "bootstrap"
  eks_node_type         = "t3.xlarge"
  eks_node_desired_size = 2

  # ##############################
  # EKS CSI
  # ##############################
  eks_csi_service_account = "ebs-csi-controller-sa"

  # ##############################
  # Karpenter
  # ##############################
  karpenter_namespace       = "kube-system"
  karpenter_service_account = "karpenter"
  karpenter_chart_ver       = "1.6.0"

  # ##############################
  # AWS Load Balancer Controller
  # ##############################
  albc_namespace       = "kube-system"
  albc_service_account = "aws-load-balancer-controller"

  # ##############################
  # ESO
  # ##############################
  eso_namespace       = "external-secrets"
  eso_service_account = "external-secrets"

  # ##############################
  # Monitoring: Loki
  # ##############################
  loki_namespace       = "monitoring"
  loki_service_account = "loki"
  loki_bucket_name     = "${local.common_name}-loki"


  # ##############################
  # ArgoCD
  # ##############################
  argocd_namespace     = "argocd"
  argocd_repo          = "https://argoproj.github.io/argo-helm"
  argocd_chart         = "argo-cd"
  argocd_chart_version = "10.1.2"
  argocd_release       = "argocd"

  argocd_values = yamlencode({
    server = {
      service = {
        type = "ClusterIP"
      }
      # Argo Rollouts extension — adds rollout progress panels to the
      # ArgoCD UI so teams see canary state without a separate dashboard.
      extensions = {
        enabled = true
        contents = [
          {
            name = "rollout-extension"
            url  = "https://github.com/argoproj-labs/rollout-extension/releases/download/v0.3.7/extension.tar"
          }
        ]
      }
    }
  })
}




