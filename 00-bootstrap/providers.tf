provider "aws" {
  region = var.region

  # Falha antes de qualquer chamada se o profile/credencial apontar para outra conta.
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      project    = "guetto"
      layer      = "00-bootstrap"
      ephemeral  = "false"
      managed-by = "terraform"
      repository = "guetto-plataform/guetto-infra"
    }
  }
}

# Token via variável de ambiente GITHUB_TOKEN (ex.: export GITHUB_TOKEN=$(gh auth token)); nunca no código.
provider "github" {
  owner = var.github_owner
}
