terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.37"
    }
  }

  # Bucket e região vêm de accounts/<conta>/backend.hcl (local) ou do GitHub Environment (CI).
  backend "s3" {
    key          = "10-network/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}
