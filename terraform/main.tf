# =============================================================================
# main.tf — Clean Production Version
# =============================================================================

# ------------------------------------------------------------------------------
# Data Sources
# ------------------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

data "aws_subnet" "selected" {
  id = tolist(data.aws_subnets.default.ids)[0]
}

# ------------------------------------------------------------------------------
# IAM ROLE
# ------------------------------------------------------------------------------
resource "aws_iam_role" "qdrant_ec2_role" {
  name = "${var.project_name}-ec2-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.qdrant_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.qdrant_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "profile" {
  name = "${var.project_name}-profile-${var.environment}"
  role = aws_iam_role.qdrant_ec2_role.name
}

# ------------------------------------------------------------------------------
# SECURITY GROUP
# ------------------------------------------------------------------------------
resource "aws_security_group" "qdrant_sg" {
  name   = "${var.project_name}-sg-${var.environment}"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_ssh_cidr_blocks
  }

  ingress {
    from_port   = 6333
    to_port     = 6333
    protocol    = "tcp"
    cidr_blocks = var.team_cidr_blocks
  }

  ingress {
    from_port   = 6334
    to_port     = 6334
    protocol    = "tcp"
    cidr_blocks = var.team_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------------------------------------------------------------
# EC2
# ------------------------------------------------------------------------------
resource "aws_instance" "qdrant" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnet.selected.id
  vpc_security_group_ids = [aws_security_group.qdrant_sg.id]

  key_name             = var.key_pair_name
  iam_instance_profile = aws_iam_instance_profile.profile.name

  associate_public_ip_address = false

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user_data.sh", {
    qdrant_api_key = var.qdrant_api_key
  })

  depends_on = [aws_iam_instance_profile.profile]

  tags = {
    Name = "${var.project_name}-server"
  }
}

# ------------------------------------------------------------------------------
# EBS VOLUME
# ------------------------------------------------------------------------------
resource "aws_ebs_volume" "data" {
  availability_zone = aws_instance.qdrant.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
}

resource "aws_volume_attachment" "attach" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.qdrant.id
}

# ------------------------------------------------------------------------------
# ELASTIC IP
# ------------------------------------------------------------------------------
resource "aws_eip" "eip" {
  domain   = "vpc"
  instance = aws_instance.qdrant.id

  depends_on = [aws_instance.qdrant]
}
