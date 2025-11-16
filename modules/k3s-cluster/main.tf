#############################################
# k3s cluster security group 
#############################################

resource "aws_security_group" "k3s" {
	name        = "k3s-cluster-sg"
	description = "Security group for k3s cluster nodes"
	vpc_id      = var.vpc_id

	tags = merge(var.tags, {
		Name = "k3s-cluster-sg"
	})
}

# Allow all intra-cluster traffic (nodes talk freely to each other)
resource "aws_security_group_rule" "intra_cluster" {
	type              = "ingress"
	security_group_id = aws_security_group.k3s.id
	from_port         = 0
	to_port           = 0
	protocol          = "-1"
	self              = true
	description       = "Intra-cluster all traffic"
}

# Optional SSH access from provided CIDR blocks
resource "aws_security_group_rule" "ssh_in" {
	for_each          = toset(var.ssh_allowed_cidrs)
	type              = "ingress"
	security_group_id = aws_security_group.k3s.id
	from_port         = 22
	to_port           = 22
	protocol          = "tcp"
	cidr_blocks       = [each.value]
	description       = "SSH access"
}

# Egress: allow all outbound (instances reach internet for updates)
resource "aws_security_group_rule" "egress_all" {
	type              = "egress"
	security_group_id = aws_security_group.k3s.id
	from_port         = 0
	to_port           = 0
	protocol          = "-1"
	cidr_blocks       = ["0.0.0.0/0"]
	description       = "Allow all outbound"
}

# Allow nginx ingress to reach K3s NodePorts (if nginx security group provided)
resource "aws_security_group_rule" "nginx_to_nodeports" {
	count                    = var.nginx_security_group_id != "" ? 1 : 0
	type                     = "ingress"
	security_group_id        = aws_security_group.k3s.id
	from_port                = 30000
	to_port                  = 32767
	protocol                 = "tcp"
	source_security_group_id = var.nginx_security_group_id
	description              = "Allow nginx ingress to reach K3s NodePorts"
}

############################################################
# k3s cluster joining token, kubeconfig and SSM parameters
############################################################

resource "random_password" "cluster_token" {
  length  = var.cluster_token_length
  special = false
}

# Optional SSM parameter for token (created only if use_ssm_token=true)
resource "aws_ssm_parameter" "cluster_token" {
	name        = var.ssm_token_name
	type        = "SecureString"
	value       = random_password.cluster_token.result
	overwrite   = true
	description = "k3s cluster token (managed by Terraform)"
	tags        = var.tags
}

# Placeholder kubeconfig parameter (will be overwritten by user_data once k3s starts)
resource "aws_ssm_parameter" "kubeconfig_placeholder" {
  name        = var.ssm_kubeconfig_name
  type        = "SecureString"
  value       = "PENDING"
  overwrite   = true
  description = "k3s kubeconfig (initial placeholder, replaced by server user_data)"
  tags        = var.tags
}

# Placeholder ArgoCD admin password parameter (will be overwritten by user_data after ArgoCD installs)
resource "aws_ssm_parameter" "argocd_password_placeholder" {
  name        = var.ssm_argocd_password_name
  type        = "SecureString"
  value       = "PENDING"
  overwrite   = true
  description = "ArgoCD initial admin password (replaced by server user_data)"
  tags        = var.tags
}

############################################
# k3s IAM roles, for SSM Access
############################################

# IAM role & instance profile granting read access to the SSM token
resource "aws_iam_role" "k3s_nodes" {
	name  = "k3s-nodes-role"
	assume_role_policy = jsonencode({
		Version = "2012-10-17"
		Statement = [{
			Effect = "Allow"
			Principal = { Service = "ec2.amazonaws.com" }
			Action = "sts:AssumeRole"
		}]
	})
	tags = var.tags
}


resource "aws_iam_role_policy" "k3s_ssm_access" {
	name  = "k3s-ssm-read"
	role  = aws_iam_role.k3s_nodes.id
	policy = jsonencode({
		Version = "2012-10-17"
		Statement = [
			{
				Effect = "Allow"
				Action = ["ssm:GetParameter"],
				Resource = aws_ssm_parameter.cluster_token.arn
			},
			{
				Effect = "Allow"
				Action = ["ssm:PutParameter", "ssm:GetParameter"],
				Resource = aws_ssm_parameter.kubeconfig_placeholder.arn
			},
			{
				Effect = "Allow"
				Action = ["ssm:PutParameter", "ssm:GetParameter"],
				Resource = aws_ssm_parameter.argocd_password_placeholder.arn
			}
		]
	})
}

############################################
# k3s server instance 
#############################################

data "aws_ami" "amazon_linux_arm" {
	owners      = ["amazon"]
	most_recent = true
	filter {
		name   = "name"
		values = ["al2023-ami-*arm64"]
	}
	filter {
		name   = "architecture"
		values = ["arm64"]
	}
	filter {
		name   = "root-device-type"
		values = ["ebs"]
	}
}

locals {
	server_subnet_id = length(var.subnet_ids) > 0 ? var.subnet_ids[0] : null
	user_data_server = templatefile("${path.module}/user_data/server.sh", {
		ssm_token_name            = var.ssm_token_name
		ssm_kubeconfig_name       = var.ssm_kubeconfig_name
		ssm_argocd_password_name  = var.ssm_argocd_password_name
	})
}

resource "aws_instance" "server" {
	ami                    = data.aws_ami.amazon_linux_arm.id
	instance_type          = var.server_instance_type
	subnet_id              = local.server_subnet_id
	vpc_security_group_ids = [aws_security_group.k3s.id]
	key_name               = var.key_name != "" ? var.key_name : null
	user_data              = local.user_data_server
	user_data_replace_on_change = true
	iam_instance_profile   = aws_iam_instance_profile.k3s_nodes.name

	tags = merge(var.tags, {
		Name        = "k3s-server"
		Role        = "k3s-server"
		Component   = "k3s"
	})
}

# Optional association of existing Elastic IP (import allocation id). If provided we fetch current public IP and associate.
resource "aws_eip_association" "server_eip" {
	count         = var.server_eip_allocation_id != "" ? 1 : 0
	allocation_id = var.server_eip_allocation_id
	instance_id   = aws_instance.server.id
}

#############################################
# k3s agent instance
#############################################

locals {
	agent_subnet_id = length(var.subnet_ids) > 1 ? var.subnet_ids[1] : local.server_subnet_id
	user_data_agent = templatefile("${path.module}/user_data/agent.sh", {
		ssm_token_name         = var.ssm_token_name
		k3s_server_private_ip  = aws_instance.server.private_ip
	})
}

resource "aws_instance" "agent" {
	ami                    = data.aws_ami.amazon_linux_arm.id
	instance_type          = var.agent_instance_type
	subnet_id              = local.agent_subnet_id
	vpc_security_group_ids = [aws_security_group.k3s.id]
	key_name               = var.key_name != "" ? var.key_name : null
	user_data              = local.user_data_agent
	user_data_replace_on_change = true
	iam_instance_profile   = aws_iam_instance_profile.k3s_nodes.name

	tags = merge(var.tags, {
		Name      = "k3s-agent"
		Role      = "k3s-agent"
		Component = "k3s"
	})

	depends_on = [aws_instance.server]
}

resource "aws_iam_instance_profile" "k3s_nodes" {
	name  = "k3s-nodes-instance-profile"
	role  = aws_iam_role.k3s_nodes.name
}
