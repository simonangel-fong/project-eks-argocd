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
  eks_name    = local.common_name
  eks_version = "1.36"
  # Bootstrap nodes host platform controllers (Prometheus, Loki, Grafana,
  # Alertmanager, cert-manager, ESO, Karpenter, Kyverno, Istio istiod/CNI/ztunnel,
  # ArgoCD). Baseline ~6-8 vCPU. t3.xlarge x2 = 8 vCPU, comfortable.
  # Workload pods scale onto Karpenter-provisioned nodes.
  eks_node_type         = "t3.xlarge"
  eks_node_desired_size = 2

  # ##############################
  # ArgoCD
  # ##############################
  argocd_namespace = "argocd"
  argocd_repo      = "https://argoproj.github.io/argo-helm"
  argocd_chart     = "argo-cd"
  argocd_chart_ver = "10.1.2"
  argocd_release   = "argocd"

  argocd_values = yamlencode({
    server = {
      service = {
        type = "ClusterIP"
      }
    }
  })

  # ##############################
  # Karpenter
  # ##############################
  karpenter_namespace       = "kube-system"
  karpenter_service_account = "karpenter"
  karpenter_chart_ver       = "1.6.0"
}




