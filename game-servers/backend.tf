terraform {
  required_version = "1.15.8"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.70.0"
    }
  }
  # Backend left empty so you pass -backend-config values at init time.
  # Use game-servers/backend.hcl (gitignored) with key = "game-servers/terraform.tfstate".
  backend "s3" {}
}
