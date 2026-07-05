data "aws_caller_identity" "current" {}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.eks_name
  kubernetes_version = local.eks_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_private_access      = true
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.cluster_public_access_cidrs

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  addons = {
    vpc-cni    = {}
    coredns    = {}
    kube-proxy = {}
    aws-ebs-csi-driver = { pod_identity_association = [{
      role_arn        = module.ebs_csi_pod_identity.iam_role_arn
      service_account = "ebs-csi-controller-sa"
    }] }
    metrics-server         = {}
    eks-pod-identity-agent = {}
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [local.eks_node_type]
      capacity_type  = "ON_DEMAND"

      min_size     = 1
      max_size     = 5
      desired_size = local.eks_node_desired_size

      subnet_ids = module.vpc.private_subnets
    }
  }
}

module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name                      = local.common_name
  attach_aws_ebs_csi_policy = true
}

resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type = "gp3"
  }

  depends_on = [module.eks]
}
