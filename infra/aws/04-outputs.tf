# output "vpc_id" {
#   description = "VPC ID."
#   value       = module.vpc.vpc_id
# }

output "placeholder_tg_arn" {
  description = "Placeholder target group ARN — paste into TargetGroupBinding manifest (7.5)."
  value       = aws_lb_target_group.placeholder.arn
}

# output "private_subnet_ids" {
#   description = "Private subnet IDs (workloads + private ALB)."
#   value       = module.vpc.private_subnets
# }

# output "public_subnet_ids" {
#   description = "Public subnet IDs (NAT gateway only)."
#   value       = module.vpc.public_subnets
# }

# output "cluster_name" {
#   description = "EKS cluster name."
#   value       = module.eks.cluster_name
# }

# output "cluster_endpoint" {
#   description = "EKS API endpoint."
#   value       = module.eks.cluster_endpoint
# }

# output "cluster_oidc_issuer_url" {
#   description = "EKS OIDC issuer URL."
#   value       = module.eks.cluster_oidc_issuer_url
# }

# output "kubeconfig_command" {
#   description = "Command to update local kubeconfig."
#   value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
# }


# # ##############################
# # ArgoCD
# # ##############################
# output "argocd_namespace" {
#   description = "Namespace where ArgoCD is installed."
#   value       = kubernetes_namespace_v1.argocd.metadata[0].name
# }

# output "argocd_server_hostname" {
#   description = "ArgoCD server LoadBalancer hostname."
#   value       = try(data.kubernetes_service_v1.argocd_server.status[0].load_balancer[0].ingress[0].hostname, "")
# }

# output "argocd_admin_password" {
#   description = "Initial ArgoCD admin password."
#   value       = try(nonsensitive(base64decode(data.kubernetes_secret_v1.argocd_admin.data.password)), "")
#   sensitive   = true
# }

# output "cmd_argocd_login" {
#   description = "Command to login to ArgoCD server."
#   value       = "argocd login ${try(data.kubernetes_service_v1.argocd_server.status[0].load_balancer[0].ingress[0].hostname, "<pending>")} --username admin --insecure"
# }

