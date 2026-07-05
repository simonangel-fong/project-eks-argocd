output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (workloads + private ALB)."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs (NAT gateway only)."
  value       = module.vpc.public_subnets
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_oidc_issuer_url" {
  description = "EKS OIDC issuer URL."
  value       = module.eks.cluster_oidc_issuer_url
}

output "kubeconfig_command" {
  description = "Command to update local kubeconfig."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "argocd_server_url" {
  description = "ArgoCD server URL (managed via EKS capability)."
  value       = module.argocd_eks_capability.argocd_server_url
}

output "argocd_iam_role_arn" {
  description = "IAM role assumed by the ArgoCD EKS capability."
  value       = module.argocd_eks_capability.iam_role_arn
}
