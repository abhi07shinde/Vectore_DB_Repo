# 1. Create a simple dedicated VPC
resource "aws_vpc" "qdrant" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "qdrant-vpc" }
}

# 2. Create a Subnet
resource "aws_subnet" "qdrant" {
  vpc_id                  = aws_vpc.qdrant.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags = { Name = "qdrant-subnet" }
}

# 3. Internet Access
resource "aws_internet_gateway" "qdrant" {
  vpc_id = aws_vpc.qdrant.id
}

resource "aws_route_table" "qdrant" {
  vpc_id = aws_vpc.qdrant.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.qdrant.id
  }
}

resource "aws_route_table_association" "qdrant" {
  subnet_id      = aws_subnet.qdrant.id
  route_table_id = aws_route_table.qdrant.id
}

# 4. Security Group
resource "aws_security_group" "qdrant" {
  name        = "qdrant-sg"
  vpc_id      = aws_vpc.qdrant.id

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

# 5. EC2 Server
resource "aws_instance" "qdrant" {
  ami                    = "ami-0084a47cc718c111a" # Ubuntu 22.04 for eu-central-1
  instance_type          = "t3.medium"
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.qdrant.id]
  subnet_id              = aws_subnet.qdrant.id

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

# 6. Public IP
resource "aws_eip" "qdrant" {
  instance = aws_instance.qdrant.id
  domain   = "vpc"
}
