# =============================================================================
# outputs.tf — Output Variables
# These are printed after terraform apply completes
# Also available in GitHub Actions logs
# =============================================================================

output "ec2_instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.qdrant.id
}

output "ec2_availability_zone" {
  description = "Availability zone of the EC2 instance"
  value       = aws_instance.qdrant.availability_zone
}

output "ec2_public_ip" {
  description = "Public IP of the EC2 instance (changes on stop/start if no Elastic IP)"
  value       = aws_instance.qdrant.public_ip
}

output "elastic_ip" {
  description = "Stable Elastic IP address (does not change on reboot)"
  value       = var.enable_elastic_ip ? aws_eip.qdrant_eip[0].public_ip : "Elastic IP not enabled"
}

output "qdrant_endpoint" {
  description = "Qdrant HTTP API endpoint — use this in your applications"
  value       = var.enable_elastic_ip ? "http://${aws_eip.qdrant_eip[0].public_ip}:6333" : "http://${aws_instance.qdrant.public_ip}:6333"
}

output "qdrant_grpc_endpoint" {
  description = "Qdrant gRPC endpoint (for high-performance use cases)"
  value       = var.enable_elastic_ip ? "${aws_eip.qdrant_eip[0].public_ip}:6334" : "${aws_instance.qdrant.public_ip}:6334"
}

output "qdrant_dashboard_url" {
  description = "Qdrant Web Dashboard — open in browser to explore collections"
  value       = var.enable_elastic_ip ? "http://${aws_eip.qdrant_eip[0].public_ip}:6333/dashboard" : "http://${aws_instance.qdrant.public_ip}:6333/dashboard"
}

output "ssh_command" {
  description = "SSH command to connect to the EC2 instance"
  value       = var.enable_elastic_ip ? "ssh -i ~/.ssh/<your-key>.pem ubuntu@${aws_eip.qdrant_eip[0].public_ip}" : "ssh -i ~/.ssh/<your-key>.pem ubuntu@${aws_instance.qdrant.public_ip}"
}

output "ebs_data_volume_id" {
  description = "EBS data volume ID (for snapshots and backups)"
  value       = aws_ebs_volume.qdrant_data.id
}

output "security_group_id" {
  description = "Security group ID (update CIDR rules here if your IP changes)"
  value       = aws_security_group.qdrant_sg.id
}

output "iam_role_arn" {
  description = "IAM role ARN attached to the EC2 instance"
  value       = aws_iam_role.qdrant_ec2_role.arn
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for EC2 bootstrap logs"
  value       = var.enable_cloudwatch ? aws_cloudwatch_log_group.qdrant_logs[0].name : "CloudWatch not enabled"
}

output "quick_test_command" {
  description = "Quick curl command to verify Qdrant is running (replace API_KEY)"
  value       = var.enable_elastic_ip ? "curl -H 'api-key: YOUR_QDRANT_API_KEY' http://${aws_eip.qdrant_eip[0].public_ip}:6333/healthz" : "curl -H 'api-key: YOUR_QDRANT_API_KEY' http://${aws_instance.qdrant.public_ip}:6333/healthz"
}
