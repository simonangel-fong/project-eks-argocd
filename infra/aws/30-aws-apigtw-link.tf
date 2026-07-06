# aws-apigtw-link.tf

# ####################
# API GTW: VPC Link
# ####################
resource "aws_security_group" "alb" {
  name        = "${local.common_name}-alb"
  description = "Private ALB fronted by API Gateway VPC Link."
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "HTTP from VPC Link SG."
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.vpc_link.id]
  }

  egress {
    description = "All egress to VPC (to node group)."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.vpc_cidr]
  }

  tags = merge(
    { Name = "${local.common_name}-alb" },
    local.default_tags
  )
}

resource "aws_apigatewayv2_vpc_link" "this" {
  name               = local.common_name
  security_group_ids = [aws_security_group.vpc_link.id]
  subnet_ids         = module.vpc.private_subnets
}
