# vpc.tf
module "vpc" {
  source = "git::https://github.com/simonangel-fong/terraform-template.git//aws/vpc-dev"

  name       = local.common_name
  cidr_block = "10.0.0.0/16"
  az_count   = 3

  tags = local.default_tags
}
