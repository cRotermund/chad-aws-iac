output "vpc_id" {
  description = "Adopted VPC id"
  value       = data.aws_vpc.existing.id
}

output "public_subnet_ids" {
  description = "List of adopted public subnet IDs"
  value       = [for s in data.aws_subnet.public : s.id]
}

output "k3s_security_group_id" {
  description = "Security group ID for k3s cluster"
  value       = module.k3s.security_group_id
}

output "k3s_server_instance_id" {
  description = "Instance ID of k3s server"
  value       = module.k3s.server_instance_id
}

output "k3s_server_public_ip" {
  description = "Public IP address of k3s server"
  value       = module.k3s.server_public_ip
}

output "k3s_agent_instance_id" {
  description = "Instance ID of k3s agent"
  value       = module.k3s.agent_instance_id
}

output "k3s_agent_public_ip" {
  description = "Public IP address of k3s agent"
  value       = module.k3s.agent_public_ip
}

output "aws_region" {
  description = "AWS region in use"
  value       = var.aws_region
}

data "aws_ssm_parameter" "kubeconfig" {
  name            = var.ssm_kubeconfig_name
  with_decryption = true
  depends_on      = [module.k3s]  # ensure cluster creation/user_data runs first
}

output "kubeconfig" {
  description = "k3s cluster kubeconfig (sanitized with public IP). Save with: terraform output -raw kubeconfig > kubeconfig.yaml"
  value       = data.aws_ssm_parameter.kubeconfig.value
  sensitive   = true
}

output "kubeconfig_ssm_parameter_name" {
  description = "Name of SSM parameter holding kubeconfig"
  value       = var.ssm_kubeconfig_name
}

# nginx ingress outputs
output "nginx_eip" {
  description = "Elastic IP address for nginx ingress (static)"
  value       = aws_eip.nginx.public_ip
}

output "nginx_eip_allocation_id" {
  description = "Allocation ID of the nginx Elastic IP"
  value       = aws_eip.nginx.allocation_id
}

output "nginx_instance_id" {
  description = "Instance ID of nginx ingress node"
  value       = module.nginx_ingress.instance_id
}

output "nginx_public_ip" {
  description = "Public IP address of nginx ingress node (static EIP)"
  value       = module.nginx_ingress.public_ip
}

output "nginx_security_group_id" {
  description = "Security group ID for nginx ingress"
  value       = module.nginx_ingress.security_group_id
}