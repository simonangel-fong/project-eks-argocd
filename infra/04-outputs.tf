# outputs.tf

# ##############################
# EKS
# ##############################
output "kubeconfig_command" {
  description = "Command to update local kubeconfig."
  value       = "aws eks update-kubeconfig --region ${local.region} --name ${module.eks.cluster_name}"
}

# ##############################
# Karpenter
# ##############################
output "karpenter_node_iam_role_name" {
  description = "Node IAM role name."
  value       = module.karpenter.node_iam_role_name
}


# # # ##############################
# # # Karpenter (7.6) — paste these into argocd/apps/karpenter.yaml values
# # # ##############################
# # output "karpenter_cluster_name" {
# #   description = "EKS cluster name — karpenter chart settings.clusterName."
# #   value       = module.eks.cluster_name
# # }

# # output "karpenter_cluster_endpoint" {
# #   description = "EKS API endpoint — karpenter chart settings.clusterEndpoint."
# #   value       = module.eks.cluster_endpoint
# # }

# # output "karpenter_queue_name" {
# #   description = "SQS interruption queue name — karpenter chart settings.interruptionQueue."
# #   value       = module.karpenter.queue_name
# # }


# ##############################
# ArgoCD
# ##############################
output "argocd_namespace" {
  description = "Namespace where ArgoCD is installed."
  value       = module.argocd.namespace
}
