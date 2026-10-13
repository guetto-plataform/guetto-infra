# Acesso da CI (GitHub Actions) à AWS sem chaves: federação OIDC (ADR-0012).

locals {
  github_environment = "aws-${var.account_name}"

  # Formato com IDs imutáveis de owner e repositório (repos criados após 15/07/2026).
  # Um job só recebe este sub se declarar `environment: aws-<conta>` — e o environment só aceita o main.
  github_oidc_subject = format(
    "repo:%s@%s/%s@%s:environment:%s",
    var.github_owner, var.github_owner_id,
    var.github_repository, data.github_repository.infra.repo_id,
    local.github_environment,
  )
}

# Registra o GitHub como emissor confiável de identidades nesta conta.
# thumbprint_list omitido: a AWS valida o certificado do GitHub pela própria cadeia de CAs.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "ci_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # O controle de segurança principal: sem ele, qualquer repositório do GitHub assumiria esta role.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.github_oidc_subject]
    }
  }
}

resource "aws_iam_role" "ci" {
  name               = "guetto-github-actions"
  description        = "Assumida pelo GitHub Actions (environment ${local.github_environment}) via OIDC."
  assume_role_policy = data.aws_iam_policy_document.ci_trust.json

  # 2h: um `up` completo (rede + EKS) não pode perder a credencial no meio do apply.
  max_session_duration = 7200
}

# Risco aceito (ADR-0012): criar EKS exige IAM, EC2, KMS, Logs etc.; least-privilege fica para a Fase 5
# com permission boundary.
resource "aws_iam_role_policy_attachment" "ci_admin" {
  role       = aws_iam_role.ci.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Deny explícito vence Allow. São quebra-molas, não muros: uma role admin ainda pode criar OUTRA role
# sem estas restrições. Evitam acidentes e abuso simples da camada persistente.
data "aws_iam_policy_document" "ci_guardrails" {
  statement {
    sid       = "DenyChangesToOwnAccess"
    effect    = "Deny"
    actions   = ["iam:*"]
    resources = [aws_iam_role.ci.arn, aws_iam_openid_connect_provider.github.arn]
  }

  statement {
    sid       = "DenyBudgetChanges"
    effect    = "Deny"
    actions   = ["budgets:ModifyBudget"]
    resources = [aws_budgets_budget.custo_bruto.arn]
  }

  statement {
    sid       = "DenyBootstrapState"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = ["${aws_s3_bucket.state.arn}/00-bootstrap/*"]
  }

  statement {
    sid    = "DenyStateBucketConfig"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket*",
      "s3:PutBucket*",
      "s3:PutLifecycleConfiguration",
      "s3:PutEncryptionConfiguration",
    ]
    resources = [aws_s3_bucket.state.arn]
  }
}

resource "aws_iam_role_policy" "ci_guardrails" {
  name   = "guardrails"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci_guardrails.json
}
