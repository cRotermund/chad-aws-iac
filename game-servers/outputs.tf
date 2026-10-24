output "vpc_id" {
  description = "Game server VPC ID"
  value       = aws_vpc.game.id
}

output "public_subnet_id" {
  description = "Public subnet ID for the game server"
  value       = aws_subnet.public.id
}

output "satisfactory_instance_id" {
  description = "Satisfactory EC2 instance ID"
  value       = aws_instance.satisfactory.id
}

output "satisfactory_public_ip" {
  description = "Satisfactory public IP (Terraform-owned EIP)"
  value       = aws_eip.satisfactory.public_ip
}

output "satisfactory_eip_allocation_id" {
  description = "Satisfactory EIP allocation ID"
  value       = aws_eip.satisfactory.id
}

output "satisfactory_security_group_id" {
  description = "Satisfactory security group ID"
  value       = aws_security_group.satisfactory.id
}
