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
    k3s_server_private_ip = var.k3s_server_private_ip
  })
}

resource "aws_instance" "nginx" {
  ami                    = data.aws_ami.amazon_linux_arm.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.nginx.id]
  key_name               = var.key_name != "" ? var.key_name : null
  user_data              = local.user_data_nginx
  user_data_replace_on_change = true

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
