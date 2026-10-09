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

output "k3s_service_account_issuer" {
  description = "OIDC issuer URL configured for Kubernetes service-account tokens"
  value       = var.k3s_service_account_issuer
}

output "k3s_oidc_provider_arn" {
  description = "AWS IAM OIDC provider ARN for the K3s service-account issuer"
  value       = aws_iam_openid_connect_provider.k3s.arn
}

output "k3s_oidc_test_role_arn" {
  description = "IAM role ARN restricted to the configured K3s OIDC test service account"
  value       = aws_iam_role.k3s_oidc_test.arn
}

data "aws_ssm_parameter" "kubeconfig" {
  name            = var.ssm_kubeconfig_name
  with_decryption = true
  depends_on      = [module.k3s] # ensure cluster creation/user_data runs first
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

# ArgoCD outputs
data "aws_ssm_parameter" "argocd_password" {
  name            = var.ssm_argocd_password_name
  with_decryption = true
  depends_on      = [module.k3s]
}

output "argocd_admin_password" {
  description = "ArgoCD initial admin password. Retrieve with: terraform output -raw argocd_admin_password"
  value       = data.aws_ssm_parameter.argocd_password.value
  sensitive   = true
}

output "argocd_server_url" {
  description = "ArgoCD server URL (accessible via nginx reverse proxy)"
  value       = "https://admin.rotorlabs.io/argocd"
}

output "argocd_ssm_parameter_name" {
  description = "Name of SSM parameter holding ArgoCD admin password"
  value       = var.ssm_argocd_password_name
}

# nginx ingress outputs
output "nginx_eip" {
  description = "Elastic IP address for nginx ingress (static)"
  value       = data.aws_eip.nginx.public_ip
}

output "nginx_eip_allocation_id" {
  description = "Allocation ID of the nginx Elastic IP"
  value       = data.aws_eip.nginx.id
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
