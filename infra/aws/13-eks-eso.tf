
locals {
  eso_test_secret_name = "eks-argocd/test/hello"
  eso_namespace        = "external-secrets"
  eso_service_account  = "external-secrets"
}


# ##############################
# IAM role: ESO
# ##############################
data "aws_iam_policy_document" "eso_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "eso_read" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.eso_test.arn]
  }
}

resource "aws_iam_role" "eso" {
  name               = "${local.common_name}-eso"
  assume_role_policy = data.aws_iam_policy_document.eso_trust.json
}

resource "aws_iam_role_policy" "eso" {
  name   = "secretsmanager-read"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso_read.json
}

resource "aws_eks_pod_identity_association" "eso" {
  cluster_name    = module.eks.cluster_name
  namespace       = local.eso_namespace
  service_account = local.eso_service_account
  role_arn        = aws_iam_role.eso.arn
}

# ################################################################################
# ESO smoke test — Secrets Manager secret + IAM + Pod Identity association
# ################################################################################
resource "aws_secretsmanager_secret" "eso_test" {
  name                    = local.eso_test_secret_name
  description             = "ESO smoke-test secret (phase 7.3)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "eso_test" {
  secret_id = aws_secretsmanager_secret.eso_test.id
  secret_string = jsonencode({
    hello = "world"
  })
}
