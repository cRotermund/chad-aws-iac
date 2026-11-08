output "bucket_name" {
  description = "Name of the Paprika MCP S3 bucket"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the Paprika MCP S3 bucket"
  value       = aws_s3_bucket.this.arn
}

output "role_arn" {
  description = "IAM role ARN the Paprika MCP service account assumes (AWS_ROLE_ARN)"
  value       = aws_iam_role.this.arn
}

output "snapshot_key" {
  description = "Object key the role may read and write (INDEX_S3_KEY)"
  value       = var.snapshot_key
}
