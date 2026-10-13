output "state_bucket" {
  description = "Nome do bucket do state (vai para accounts/<conta>/backend.hcl e para o GitHub Environment)."
  value       = aws_s3_bucket.state.bucket
}

output "ci_role_arn" {
  description = "Role assumida pela CI (também publicada como secret AWS_ROLE_ARN no GitHub Environment)."
  value       = aws_iam_role.ci.arn
}

output "github_oidc_subject" {
  description = "Valor exato de sub aceito pela trust policy. Útil para depurar AssumeRole negado."
  value       = local.github_oidc_subject
}
