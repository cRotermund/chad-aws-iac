output "security_group_id" {
  description = "ID of the k3s cluster security group"
  value       = aws_security_group.k3s.id
}

output "server_instance_id" {
  description = "EC2 instance ID of k3s server"
  value       = aws_instance.server.id
}

output "server_public_ip" {
  description = "Public IP of k3s server (may be EIP if associated)"
  value       = aws_instance.server.public_ip
}

output "server_private_ip" {
  description = "Private IP of k3s server"
  value       = aws_instance.server.private_ip
}

output "agent_instance_id" {
  description = "EC2 instance ID of k3s agent"
  value       = aws_instance.agent.id
}

output "agent_public_ip" {
  description = "Public IP of k3s agent"
  value       = aws_instance.agent.public_ip
}

output "cluster_token_ssm_parameter_name" {
  description = "Name of the SSM SecureString parameter storing the k3s cluster join token"
  value       = aws_ssm_parameter.cluster_token.name
}

output "kubeconfig_ssm_parameter_name" {
  description = "Name of the SSM parameter storing the kubeconfig"
  value       = aws_ssm_parameter.kubeconfig_placeholder.name
}