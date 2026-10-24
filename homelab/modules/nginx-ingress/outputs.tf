output "security_group_id" {
  description = "ID of the nginx ingress security group"
  value       = aws_security_group.nginx.id
}

output "instance_id" {
  description = "EC2 instance ID of nginx ingress node"
  value       = aws_instance.nginx.id
}

output "private_ip" {
  description = "Private IP of nginx ingress node"
  value       = aws_instance.nginx.private_ip
}

output "public_ip" {
  description = "Public IP of nginx ingress node (from associated EIP)"
  value       = aws_instance.nginx.public_ip
}
