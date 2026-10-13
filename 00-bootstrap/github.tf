# Lado GitHub do acesso da CI: um environment por conta AWS (ADR-0011/0012).

data "github_repository" "infra" {
  full_name = "${var.github_owner}/${var.github_repository}"
}

resource "github_repository_environment" "aws" {
  repository  = var.github_repository
  environment = local.github_environment

  # Faz parte da segurança: sem isto, qualquer branch poderia declarar o environment
  # e receber um token com o sub aceito pela role.
  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "main" {
  repository     = var.github_repository
  environment    = github_repository_environment.aws.environment
  branch_pattern = "main"
}

# Valores que contêm o account ID vão como secret: logs do Actions de repositório público são públicos,
# e o GitHub mascara secrets nos logs.
resource "github_actions_environment_secret" "aws" {
  for_each = {
    AWS_ROLE_ARN    = aws_iam_role.ci.arn
    TF_STATE_BUCKET = aws_s3_bucket.state.bucket
  }

  repository  = var.github_repository
  environment = github_repository_environment.aws.environment
  secret_name = each.key
  value       = each.value
}

resource "github_actions_environment_variable" "aws_region" {
  repository    = var.github_repository
  environment   = github_repository_environment.aws.environment
  variable_name = "AWS_REGION"
  value         = var.region
}
