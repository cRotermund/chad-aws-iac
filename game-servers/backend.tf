terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
  # Backend left empty so you pass -backend-config values at init time.
  # Use game-servers/backend.hcl (gitignored) with key = "game-servers/terraform.tfstate".
  backend "s3" {}
}
