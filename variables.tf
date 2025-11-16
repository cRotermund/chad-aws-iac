variable "aws_region" {
  description = "AWS region to deploy and look up resources"
  type        = string
  default     = "us-east-1"
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
    Owner      = "chad"
    Project    = "infra"
    Environment= "single"
    ManagedBy  = "terraform"
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

variable "ssm_kubeconfig_name" {
  description = "SSM SecureString parameter name to store exported kubeconfig (will be created and then overwritten by server user data)."
  type        = string
  default     = "/k3s/cluster/kubeconfig"
}

# nginx ingress variables
variable "nginx_instance_type" {
  description = "Instance type for the nginx ingress node"
  type        = string
  default     = "t4g.micro"
}