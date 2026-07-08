# ################################################################################
# AWS Load Balancer Controller — IAM + Pod Identity
# ################################################################################

locals {
  albc_namespace       = "kube-system"
  albc_service_account = "aws-load-balancer-controller"
}

# AWS-published policy JSON (pin to a known-good release)
data "http" "albc_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.9.2/docs/install/iam_policy.json"
}

data "aws_iam_policy_document" "albc_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "albc" {
  name               = "${local.common_name}-albc"
  assume_role_policy = data.aws_iam_policy_document.albc_trust.json
}

resource "aws_iam_policy" "albc" {
  name   = "${local.common_name}-albc"
  policy = data.http.albc_policy.response_body
}

resource "aws_iam_role_policy_attachment" "albc" {
  role       = aws_iam_role.albc.name
  policy_arn = aws_iam_policy.albc.arn
}

resource "aws_eks_pod_identity_association" "albc" {
  cluster_name    = module.eks.cluster_name
  namespace       = local.albc_namespace
  service_account = local.albc_service_account
  role_arn        = aws_iam_role.albc.arn
}
