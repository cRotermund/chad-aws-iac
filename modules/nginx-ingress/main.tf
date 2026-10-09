###############################################
# nginx ingress/load balancer security group
###############################################

resource "aws_security_group" "nginx" {
  name        = "nginx-ingress-sg"
  description = "Security group for nginx ingress/load balancer node"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "nginx-ingress-sg"
  })
}

# HTTP ingress from anywhere
resource "aws_security_group_rule" "http_in" {
  type              = "ingress"
  security_group_id = aws_security_group.nginx.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTP from internet"
}

# HTTPS ingress from anywhere
resource "aws_security_group_rule" "https_in" {
  type              = "ingress"
  security_group_id = aws_security_group.nginx.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTPS from internet"
}

# Optional SSH access from provided CIDR blocks
resource "aws_security_group_rule" "ssh_in" {
  for_each          = toset(var.ssh_allowed_cidrs)
  type              = "ingress"
  security_group_id = aws_security_group.nginx.id
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [each.value]
  description       = "SSH access"
}

# Egress: allow all outbound
resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.nginx.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all outbound"
}

###############################################
# nginx ingress EC2 instance
###############################################

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
  user_data_nginx = templatefile("${path.module}/user_data/nginx.sh", {
    k3s_server_private_ip     = var.k3s_server_private_ip
    tls_certificate_parameter = var.tls_certificate_parameter_name
    tls_ca_bundle_parameter   = var.tls_ca_bundle_parameter_name
    tls_private_key_parameter = var.tls_private_key_parameter_name
  })
}

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  tls_parameter_arns = [
    "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:parameter${var.tls_certificate_parameter_name}",
    "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:parameter${var.tls_ca_bundle_parameter_name}",
    "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:parameter${var.tls_private_key_parameter_name}",
  ]
}

resource "aws_iam_role" "nginx" {
  name = "nginx-ingress-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "nginx_tls_access" {
  name = "nginx-tls-ssm-read"
  role = aws_iam_role.nginx.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = local.tls_parameter_arns
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = var.tls_kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "nginx_ssm_core" {
  role       = aws_iam_role.nginx.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nginx" {
  name = "nginx-ingress-profile"
  role = aws_iam_role.nginx.name
  tags = var.tags
}

resource "aws_instance" "nginx" {
  ami                         = data.aws_ami.amazon_linux_arm.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.nginx.id]
  key_name                    = var.key_name != "" ? var.key_name : null
  user_data                   = local.user_data_nginx
  user_data_replace_on_change = true
  iam_instance_profile        = aws_iam_instance_profile.nginx.name

  tags = merge(var.tags, {
    Name      = "nginx-ingress"
    Role      = "ingress"
    Component = "nginx"
  })
}

# Associate the existing Elastic IP
resource "aws_eip_association" "nginx_eip" {
  allocation_id = var.eip_allocation_id
  instance_id   = aws_instance.nginx.id
}
