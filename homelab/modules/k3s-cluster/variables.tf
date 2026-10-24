variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "server_instance_type" {
  type = string
}

variable "agent_instance_type" {
  type = string
}

variable "ami_id" {
  description = "AMI ID for K3s server and agent nodes (Amazon Linux 2023 arm64). Pinned so routine AMI releases do not replace running nodes; update deliberately."
  type        = string
  default     = "ami-05ec9e26a9c82817a"
}

variable "k3s_version" {
  description = "Exact K3s release installed on server and agent nodes (INSTALL_K3S_VERSION). A change replaces the nodes."
  type        = string
  default     = "v1.36.5+k3s1"
}

variable "awscli_package_version" {
  description = "Exact awscli-2 RPM version (name-version-release) used if the AWS CLI is missing. A change replaces the nodes."
  type        = string
  default     = "2.36.47-4.amzn2023.0.1"
}

variable "server_eip_allocation_id" {
  type    = string
  default = ""
}

variable "cluster_token_length" {
  description = "Length of the randomly generated k3s cluster join token"
  type        = number
  default     = 40
}

variable "tags" {
  type = map(string)
}

variable "ssh_allowed_cidrs" {
  description = "List of CIDR blocks allowed SSH access (e.g. your workstation IP /32). Leave empty to disable SSH ingress."
  type        = list(string)
  default     = []
}

variable "kubectl_allowed_cidrs" {
  description = "List of CIDR blocks allowed for kubectl (6443) access. (e.g. your workstation IP /32).  Leave empty to disable kubectl access."
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

variable "nginx_security_group_id" {
  description = "Security group ID of nginx ingress to allow traffic to K3s NodePorts"
  type        = string
  default     = ""
}

variable "create_nginx_nodeport_rule" {
  description = "Whether to create a security group rule allowing nginx ingress to NodePorts"
  type        = bool
  default     = false
}

variable "ssm_argocd_password_name" {
  description = "SSM parameter name to store ArgoCD initial admin password (e.g. /k3s/argocd/password)"
  type        = string
}

variable "service_account_issuer" {
  description = "Stable OIDC issuer URL configured on the k3s API server"
  type        = string
}
