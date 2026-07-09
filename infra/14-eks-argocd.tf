# argocd.tf

module "argocd" {
  source = "git::https://github.com/simonangel-fong/terraform-template.git//kubernetes/argocd"

  argocd_version = local.argocd_chart_version
  namespace      = local.argocd_namespace
  extra_values   = local.argocd_values

  depends_on = [module.eks]
}
