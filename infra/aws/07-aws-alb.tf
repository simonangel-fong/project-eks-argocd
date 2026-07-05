# aws-alb.tf


# ####################
# Security Group
# ####################
resource "aws_security_group" "vpc_link" {
  name        = "${local.common_name}-vpc-link"
  description = "API Gateway HTTP API VPC Link."
  vpc_id      = module.vpc.vpc_id

  egress {
    description = "To private ALB."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.vpc_cidr]
  }

  tags = merge(
    { Name = "${local.common_name}-vpc-link" },
    local.default_tags
  )
}

# ####################
# ALB
# ####################
resource "aws_lb" "private" {
  name               = "${local.common_name}-alb"
  internal           = true
  load_balancer_type = "application"
  subnets            = module.vpc.private_subnets
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.private.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.placeholder.arn
  }
}

# ####################
# Target Group
# ####################
resource "aws_lb_target_group" "placeholder" {
  name        = "${local.common_name}-placeholder"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    matcher             = "200-499"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }
}
