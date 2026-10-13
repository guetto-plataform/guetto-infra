provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      project    = "guetto"
      layer      = "10-network"
      ephemeral  = "true"
      managed-by = "terraform"
      repository = "guetto-plataform/guetto-infra"
    }
  }
}
