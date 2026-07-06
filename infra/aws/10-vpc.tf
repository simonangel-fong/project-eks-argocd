module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.common_name
  cidr = local.vpc_cidr
  azs  = local.subnet_azs

  private_subnets = ["10.0.0.0/20", "10.0.16.0/20"]
  public_subnets  = ["10.0.240.0/24", "10.0.241.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"         = 1
    "kubernetes.io/cluster/${local.eks_name}" = "shared"
  }
}
