output "instance_id" {
  description = "Use with: aws ssm start-session --target <instance_id>"
  value       = aws_instance.host.id
}

output "public_ip" {
  description = "Fixed public IP of the lab host"
  value       = aws_eip.host.public_ip
}

output "staging_url" {
  description = "Staging app URL (sslip.io = free DNS that maps the name to the IP)"
  value       = "http://staging.${replace(aws_eip.host.public_ip, ".", "-")}.sslip.io"
}

output "production_lab_url" {
  description = "Production-lab app URL"
  value       = "http://prod.${replace(aws_eip.host.public_ip, ".", "-")}.sslip.io"
}

output "ecr_repository_url" {
  description = "Where CI pushes the app image"
  value       = aws_ecr_repository.app.repository_url
}

output "github_actions_role_arn" {
  description = "Set as GitHub repository variable AWS_ROLE_ARN"
  value       = aws_iam_role.github_ecr_push.arn
}

output "backup_bucket" {
  description = "Encrypted S3 bucket for database backups"
  value       = aws_s3_bucket.backups.bucket
}
