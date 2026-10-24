locals {
  game_port_ingress_protocols = toset(["tcp", "udp"])
}

# Dedicated network for game servers (ADR 007). No peering to the homelab VPC.
resource "aws_vpc" "game" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "game-servers-vpc"
  }
}

resource "aws_internet_gateway" "game" {
  vpc_id = aws_vpc.game.id

  tags = {
    Name = "game-servers-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.game.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "game-servers-public-a"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.game.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.game.id
  }

  tags = {
    Name = "game-servers-public"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security group for the Satisfactory server. Game ports are open to the internet
# by design; SSH is restricted to var.ssh_allowed_cidrs.
resource "aws_security_group" "satisfactory" {
  name        = "satisfactory-sg"
  description = "Satisfactory dedicated server: game port from internet, SSH from operator CIDRs"
  vpc_id      = aws_vpc.game.id

  tags = {
    Name = "satisfactory-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "game" {
  for_each          = local.game_port_ingress_protocols
  security_group_id = aws_security_group.satisfactory.id
  description       = "Satisfactory game port (${each.key})"
  from_port         = var.game_port
  to_port           = var.game_port
  ip_protocol       = each.key
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "reliable" {
  security_group_id = aws_security_group.satisfactory.id
  description       = "Satisfactory reliable messaging (tcp)"
  from_port         = var.reliable_port
  to_port           = var.reliable_port
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each          = toset(var.ssh_allowed_cidrs)
  security_group_id = aws_security_group.satisfactory.id
  description       = "SSH from operator CIDR"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.satisfactory.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_key_pair" "game" {
  key_name   = "game-servers"
  public_key = var.ssh_public_key
}

resource "aws_instance" "satisfactory" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.satisfactory.id]
  key_name               = aws_key_pair.game.key_name

  # Matches the state AWS reports for the running instance, which has a public
  # address from the EIP. Setting false here forces replacement of the instance.
  associate_public_ip_address = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name         = "satisfactory"
    Game         = "Satisfactory"
    IsGameServer = "True"
  }
}

# The EIP is owned by this stack and imported from the existing allocation so the
# current public IP is kept. prevent_destroy guards against releasing it accidentally.
import {
  to = aws_eip.satisfactory
  id = var.eip_allocation_id
}

resource "aws_eip" "satisfactory" {
  domain = "vpc"

  tags = {
    Name = "satisfactory-eip"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_eip_association" "satisfactory" {
  allocation_id       = aws_eip.satisfactory.id
  instance_id         = aws_instance.satisfactory.id
  allow_reassociation = true
}
