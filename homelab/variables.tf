variable "aws_region" {
  description = "AWS region to deploy and look up resources"
  type        = string
  default     = "us-east-1"
}

variable "k3s_service_account_issuer" {
  description = "Stable OIDC issuer URL configured on the k3s API server"
  type        = string
  default     = "https://apis.rotorlabs.io/aws-oidc"

  validation {
    condition     = var.k3s_service_account_issuer == "https://apis.rotorlabs.io/aws-oidc"
    error_message = "The k3s service-account issuer must remain https://apis.rotorlabs.io/aws-oidc."
  }
}

variable "k3s_oidc_test_role_name" {
  description = "IAM role name used to validate K3s service-account federation"
  type        = string
  default     = "k3s-oidc-test"
}

variable "k3s_oidc_test_service_account_namespace" {
  description = "Kubernetes namespace allowed to assume the K3s OIDC test role"
  type        = string
  default     = "default"
}

variable "k3s_oidc_test_service_account_name" {
  description = "Kubernetes service account allowed to assume the K3s OIDC test role"
  type        = string
  default     = "aws-test"
}

variable "k3s_eso_auth_role_name" {
  description = "IAM role trusted by the ESO Kubernetes service account through OIDC"
  type        = string
  default     = "k3s-external-secrets-auth"
}

variable "k3s_eso_ssm_role_name" {
  description = "IAM role ESO assumes to read approved SSM parameters"
  type        = string
  default     = "k3s-ssm-parameter-read"
}

variable "k3s_eso_ssm_parameter_path" {
  description = "Inclusive SSM parameter path ESO may read"
  type        = string
  default     = "/kubernetes/appsecrets/"

  validation {
    condition = (
      startswith(var.k3s_eso_ssm_parameter_path, "/") &&
      endswith(var.k3s_eso_ssm_parameter_path, "/") &&
      !strcontains(var.k3s_eso_ssm_parameter_path, "*")
    )
    error_message = "The ESO SSM parameter path must start and end with / and must not contain wildcards."
  }
}

variable "vpc_id" {
  description = "Existing VPC ID to adopt (leave empty until known)"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of existing public subnet IDs (for k3s nodes)"
  type        = list(string)
}

variable "k3s_server_instance_type" {
  description = "Instance type for the k3s server node"
  type        = string
  default     = "t4g.medium"
}

variable "k3s_agent_instance_type" {
  description = "Instance type for the k3s agent node"
  type        = string
  default     = "t4g.medium"
}

variable "tags" {
  description = "Base tags applied to all managed resources"
  type        = map(string)
  default = {
    Owner       = "chad"
    Project     = "infra"
    Environment = "single"
    ManagedBy   = "terraform"
  }
}

variable "k3s_server_eip_allocation_id" {
  description = "Optional existing Elastic IP allocation id to attach to server (import scenario)"
  type        = string
  default     = ""
}

variable "ssm_token_name" {
  description = "Name (path) for the SSM SecureString parameter holding the k3s cluster token (Terraform will create & manage it)."
  type        = string
  default     = "/k3s/cluster/token"
}

variable "key_name" {
  description = "Existing EC2 key pair name for SSH access to k3s nodes (leave empty to disable SSH key injection)"
  type        = string
  default     = ""
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed SSH ingress to k3s nodes (e.g. your.ip.addr/32). Keep empty to block SSH."
  type        = list(string)
  default     = []
}

variable "kubectl_allowed_cidrs" {
  description = "List of CIDR blocks allowed for kubectl (6443) access. (e.g. your.ip.addr/32).  Leave empty to disable kubectl access."
  type        = list(string)
  default     = []
}

variable "ssm_kubeconfig_name" {
  description = "SSM SecureString parameter name to store exported kubeconfig (will be created and then overwritten by server user data)."
  type        = string
  default     = "/k3s/cluster/kubeconfig"
}

variable "ssm_argocd_password_name" {
  description = "SSM SecureString parameter name to store ArgoCD initial admin password (will be created and overwritten by server user data)."
  type        = string
  default     = "/k3s/argocd/password"
}

# nginx ingress variables
variable "nginx_instance_type" {
  description = "Instance type for the nginx ingress node"
  type        = string
  default     = "t4g.micro"
}

variable "nginx_eip_allocation_id" {
  description = "Existing Elastic IP allocation ID for nginx (managed outside Terraform, never destroyed)"
  type        = string
}

variable "nginx_tls_certificate_parameter_name" {
  description = "SSM SecureString parameter containing the PEM server certificate for the rotorlabs domains"
  type        = string
  default     = "/nginx/tls/rotorlabs/certificate"
}

variable "nginx_tls_ca_bundle_parameter_name" {
  description = "SSM SecureString parameter containing the PEM CA bundle for the rotorlabs domains"
  type        = string
  default     = "/nginx/tls/rotorlabs/ca-bundle"
}

variable "nginx_tls_private_key_parameter_name" {
  description = "SSM SecureString parameter containing the PEM private key for the rotorlabs domains"
  type        = string
  default     = "/nginx/tls/rotorlabs/private-key"
}

variable "nginx_tls_kms_key_arn" {
  description = "KMS key ARN used to encrypt the nginx TLS SSM parameters; use * for the AWS-managed aws/ssm key"
  type        = string
  default     = "*"
}
