# Reference existing network resources via data sources.

data "aws_vpc" "existing" {
  id = var.vpc_id
}

data "aws_subnet" "public" {
  for_each = toset(var.public_subnet_ids)
  id       = each.value
}

# Determine which AZs support the selected server instance type (e.g., t4g.small may not be in all AZs).
data "aws_ec2_instance_type_offerings" "k3s_server_type" {
  location_type = "availability-zone"
  filter {
    name   = "instance-type"
    values = [var.k3s_server_instance_type]
  }
  # Region is inherited from provider (var.aws_region)
}

locals {
  supported_azs       = data.aws_ec2_instance_type_offerings.k3s_server_type.locations
  # Keep only subnets whose AZ supports the instance type
  filtered_subnet_ids = [for s in data.aws_subnet.public : s.id if contains(local.supported_azs, s.availability_zone)]
  effective_subnet_ids = length(local.filtered_subnet_ids) > 0 ? local.filtered_subnet_ids : [for s in data.aws_subnet.public : s.id]
}

module "k3s" {
  source                   = "./modules/k3s-cluster"
  vpc_id                   = data.aws_vpc.existing.id
  subnet_ids               = local.effective_subnet_ids
  server_instance_type     = var.k3s_server_instance_type
  agent_instance_type      = var.k3s_agent_instance_type
  server_eip_allocation_id = var.k3s_server_eip_allocation_id
  ssm_token_name           = var.ssm_token_name
  ssm_kubeconfig_name      = var.ssm_kubeconfig_name
  tags                     = var.tags
  key_name                 = var.key_name
  ssh_allowed_cidrs        = var.ssh_allowed_cidrs
}
