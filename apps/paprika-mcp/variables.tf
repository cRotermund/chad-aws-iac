variable "aws_region" {
  description = "AWS region for the Paprika MCP stack"
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Tags applied to all resources via provider default_tags. Project is used for cost allocation."
  type        = map(string)
  default = {
    Owner     = "chad"
    Project   = "paprika-mcp"
    ManagedBy = "terraform"
  }
}

variable "bucket_name" {
  description = "Globally unique name of the S3 bucket used by the Paprika MCP server"
  type        = string
}

variable "role_name" {
  description = "IAM role name assumed by the Paprika MCP server"
  type        = string
  default     = "paprika-mcp"
}

variable "k3s_service_account_issuer" {
  description = "OIDC issuer URL of the homelab k3s cluster. The IAM OIDC provider is owned by the homelab stack."
  type        = string
  default     = "https://apis.rotorlabs.io/aws-oidc"
}

variable "service_account_namespace" {
  description = "Kubernetes namespace of the service account allowed to assume the role"
  type        = string
  default     = "chad-applications"
}

variable "service_account_name" {
  description = "Kubernetes service account allowed to assume the role"
  type        = string
  default     = "paprika-mcp-go"
}

variable "snapshot_key" {
  description = "S3 object key of the recipe index snapshot (INDEX_S3_KEY). The role can only read and write this one object."
  type        = string
  default     = "paprika-mcp-go/recipe-index.json.gz"
}

variable "noncurrent_version_expiration_days" {
  description = "Days before noncurrent object versions are permanently deleted"
  type        = number
  default     = 5
}
