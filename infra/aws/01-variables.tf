variable "project" {
  description = "Project name, used as a prefix for all resources."
  type        = string
  default     = "voting"
}

variable "env" {
  description = "Deployment environment (dev, prod, ...)."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "ca-central-1"
}

variable "cluster_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS public API endpoint.(curl -4 ifconfig.me)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
