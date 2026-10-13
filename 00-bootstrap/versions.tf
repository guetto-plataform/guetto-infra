terraform {
  # use_lockfile (lock nativo no S3) é GA desde a 1.11.
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # bucket_namespace (namespace regional da conta) exige >= 6.37.
      version = "~> 6.37"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }

  # Configuração parcial: bucket e região vêm de accounts/<conta>/backend.hcl.
  # No primeiro apply de uma conta o bucket ainda não existe — ver README (backend_override.tf).
  backend "s3" {
    key          = "00-bootstrap/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}
