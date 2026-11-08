terraform {
  required_version = "1.15.8"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.70.0"
    }
  }
  # Backend left empty so you pass -backend-config values at init time.
  # Use apps/paprika-mcp/backend.hcl (gitignored) with key = "apps/paprika-mcp/terraform.tfstate".
  backend "s3" {}
}
