provider "aws" {
  region                   = var.aws_region
  shared_config_files      = ["${path.module}/../aws-config"]
  shared_credentials_files = ["${path.module}/../aws-credentials"]
  profile                  = "terraform-iac"

  default_tags {
    tags = var.tags
  }
}
