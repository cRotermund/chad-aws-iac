terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
  # Backend left empty so you pass -backend-config values at init time.
  # Example (do not commit secrets or bucket names if you prefer anonymity):
  # terraform init \
  #   -backend-config="bucket=YOUR_BUCKET" \
  #   -backend-config="key=state/terraform.tfstate" \
  #   -backend-config="region=us-east-1" \
  #   -backend-config="dynamodb_table=YOUR_LOCK_TABLE" \
  #   -backend-config="encrypt=true"
  backend "s3" {}
}