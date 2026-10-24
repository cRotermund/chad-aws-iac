variable "aws_region" {
  description = "AWS region for the game server stack"
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Tags applied to all resources via provider default_tags. Project is used for cost allocation."
  type        = map(string)
  default = {
    Owner     = "chad"
    Project   = "game-servers"
    ManagedBy = "terraform"
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the dedicated game server VPC. Must not overlap the default VPC (172.31.0.0/16)."
  type        = string
  default     = "10.10.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the single public subnet"
  type        = string
  default     = "10.10.1.0/24"
}

variable "availability_zone" {
  description = "Availability zone for the public subnet and the game server instance"
  type        = string
  default     = "us-east-1a"
}

variable "instance_type" {
  description = "EC2 instance type for the game server (x86_64 required by the Satisfactory binary)"
  type        = string
  default     = "m6a.xlarge"
}

variable "ami_id" {
  description = "Debian 13 AMI ID (amd64). Pinned: change deliberately, since changing it replaces the instance."
  type        = string
  default     = "ami-0bd74f3706bb4acb8"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access. The key pair is created outside Terraform (aws ec2 create-key-pair) and the private key is stored in ~/.ssh, matching the homelab SOP."
  type        = string
  default     = "chad-game-servers"
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed SSH ingress (e.g. your.ip.addr/32). Empty disables SSH ingress."
  type        = list(string)
  default     = []
}

variable "game_port" {
  description = "Satisfactory game port, opened on both TCP and UDP from the internet"
  type        = number
  default     = 7777
}

variable "reliable_port" {
  description = "Satisfactory reliable messaging port (TCP), opened from the internet. Without it, players stall on the loading screen (wiki: Dedicated servers, patch 1.1.0.0+)."
  type        = number
  default     = 8888
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GiB (gp3). 16 GiB is the minimum-cost choice; see ADR 009."
  type        = number
  default     = 16
}

variable "eip_allocation_id" {
  description = "Existing Elastic IP allocation ID for the game server. Managed outside Terraform (never created or released here), matching the homelab."
  type        = string
}
