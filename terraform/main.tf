data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "qdrant" {
  name        = "qdrant-sg"
  description = "Security group for Qdrant"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    from_port   = 6333
    to_port     = 6333
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "qdrant" {
  ami                    = "ami-0dee22c13ea7a9a67"
  instance_type          = "t3.medium"
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.qdrant.id]
  subnet_id              = tolist(data.aws_subnets.default.ids)[0]

  root_block_device {
    volume_size = 40
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker
              docker run -d --name qdrant --restart always -p 6333:6333 -e QDRANT__SERVICE__API_KEY=${var.qdrant_api_key} qdrant/qdrant:latest
              EOF

  tags = {
    Name = "qdrant-server"
  }
}

resource "aws_eip" "qdrant" {
  instance = aws_instance.qdrant.id
  domain   = "vpc"
}
