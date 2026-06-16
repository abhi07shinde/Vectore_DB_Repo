output "public_ip" {
  value = aws_eip.qdrant.public_ip
}

output "qdrant_endpoint" {
  value = "http://${aws_eip.qdrant.public_ip}:6333"
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/your-key.pem ubuntu@${aws_eip.qdrant.public_ip}"
}
