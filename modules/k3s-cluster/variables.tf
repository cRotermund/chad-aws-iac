variable "vpc_id" { type = string }

variable "subnet_ids" { type = list(string) }

variable "server_instance_type" { type = string }

variable "agent_instance_type" { type = string }

variable "server_eip_allocation_id" { 
    type = string 
    default = "" 
}

variable "cluster_token_length" {
  description = "Length of the randomly generated k3s cluster join token"
  type        = number
  default     = 40
}

variable "tags" { type = map(string) }

variable "ssh_allowed_cidrs" {
  description = "List of CIDR blocks allowed SSH access (e.g. your workstation IP /32). Leave empty to disable SSH ingress."
  type        = list(string)
  default     = []
}

variable "key_name" {
  description = "Optional existing EC2 key pair name for SSH access to server node"
  type        = string
  default     = ""
}

variable "ssm_token_name" {
  description = "SSM parameter name to store the k3s cluster join token (e.g. /k3s/cluster/token)"
  type        = string
}

variable "ssm_kubeconfig_name" {
  description = "SSM parameter name to store exported kubeconfig (e.g. /k3s/cluster/kubeconfig)"
  type        = string
}