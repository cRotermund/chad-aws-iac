variable "vpc_id" {
  description = "VPC ID where the nginx instance will be deployed"
  type        = string
}

variable "subnet_id" {
  description = "Public subnet ID for the nginx instance"
  type        = string
}

variable "instance_type" {
  description = "Instance type for the nginx ingress node"
  type        = string
  default     = "t4g.micro"
}

variable "eip_allocation_id" {
  description = "Existing Elastic IP allocation ID to attach to nginx instance (required for static IP)"
  type        = string
}

variable "k3s_server_private_ip" {
  description = "Private IP address of the k3s server for upstream proxy configuration"
  type        = string
}

variable "key_name" {
  description = "Optional existing EC2 key pair name for SSH access"
  type        = string
  default     = ""
}

variable "ssh_allowed_cidrs" {
  description = "List of CIDR blocks allowed SSH access (e.g. your workstation IP /32). Leave empty to disable SSH ingress."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
