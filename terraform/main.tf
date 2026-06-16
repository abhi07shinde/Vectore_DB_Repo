# =============================================================================
# main.tf — Core Infrastructure
# Resources: VPC (default), Security Group, IAM Role, EC2, EBS, Elastic IP
# =============================================================================

# ------------------------------------------------------------------------------
# Data Sources
# ------------------------------------------------------------------------------

# Use the default VPC — no need to create a new one
data "aws_vpc" "default" {
  default = true
}

# Get all subnets in the default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Get the first available subnet
data "aws_subnet" "selected" {
  id = tolist(data.aws_subnets.default.ids)[0]
}

# ------------------------------------------------------------------------------
# IAM Role for EC2 (CloudWatch + SSM access)
# ------------------------------------------------------------------------------

resource "aws_iam_role" "qdrant_ec2_role" {
  name = "${var.project_name}-ec2-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ec2-role"
  }
}

# Attach CloudWatch Agent policy
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.qdrant_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Attach SSM policy (allows browser-based SSH via AWS Console without opening port 22)
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.qdrant_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create instance profile
resource "aws_iam_instance_profile" "qdrant_profile" {
  name = "${var.project_name}-instance-profile-${var.environment}"
  role = aws_iam_role.qdrant_ec2_role.name

  tags = {
    Name = "${var.project_name}-instance-profile"
  }
}

# ------------------------------------------------------------------------------
# Security Group
# ------------------------------------------------------------------------------

resource "aws_security_group" "qdrant_sg" {
  name        = "${var.project_name}-sg-${var.environment}"
  description = "Security group for Qdrant vector database server"
  vpc_id      = data.aws_vpc.default.id

  # SSH access — restricted to admin IPs only
  ingress {
    description = "SSH from admin IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_ssh_cidr_blocks
  }

  # Qdrant HTTP API — accessible by the whole team
  ingress {
    description = "Qdrant API access for team"
    from_port   = 6333
    to_port     = 6333
    protocol    = "tcp"
    cidr_blocks = var.team_cidr_blocks
  }

  # Qdrant gRPC — accessible by the whole team
  ingress {
    description = "Qdrant gRPC access for team"
    from_port   = 6334
    to_port     = 6334
    protocol    = "tcp"
    cidr_blocks = var.team_cidr_blocks
  }

  # All outbound traffic allowed
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# ------------------------------------------------------------------------------
# CloudWatch Log Group
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "qdrant_logs" {
  count             = var.enable_cloudwatch ? 1 : 0
  name              = "/qdrant/ec2/user-data"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = {
    Name = "${var.project_name}-logs"
  }
}

# ------------------------------------------------------------------------------
# EC2 Instance
# ------------------------------------------------------------------------------

resource "aws_instance" "qdrant" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnet.selected.id
  vpc_security_group_ids      = [aws_security_group.qdrant_sg.id]
  key_name                    = var.key_pair_name
  iam_instance_profile        = aws_iam_instance_profile.qdrant_profile.name
  associate_public_ip_address = true

  # Monitoring
  monitoring = var.enable_cloudwatch

  # Root volume — OS + Docker images
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.project_name}-root-volume"
    }
  }

  # User data — bootstrap script (Docker + Qdrant)
  # qdrant_api_key is injected as a template variable
  user_data = templatefile("${path.module}/user_data.sh", {
    qdrant_api_key = var.qdrant_api_key
  })

  # Ensure IAM profile is ready before instance launches
  depends_on = [aws_iam_instance_profile.qdrant_profile]

  tags = {
    Name         = "${var.project_name}-server"
    Role         = "vector-database"
    BackupPolicy = "daily"
  }

  lifecycle {
    # Prevent accidental destruction of the instance
    # Change to false if you need to replace the instance
    prevent_destroy = false

    # Replace instance if user_data changes
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------------------
# EBS Data Volume — Qdrant persistent storage (separate from root)
# This ensures data survives even if the instance is replaced
# ------------------------------------------------------------------------------

resource "aws_ebs_volume" "qdrant_data" {
  availability_zone = aws_instance.qdrant.availability_zone
  size              = var.data_volume_size
  type              = var.data_volume_type
  encrypted         = true

  # gp3 performance settings (free baseline)
  throughput = 125  # MB/s (gp3 default, free tier)
  iops       = 3000 # IOPS (gp3 default, free tier)

  tags = {
    Name         = "${var.project_name}-data-volume"
    Role         = "qdrant-storage"
    BackupPolicy = "daily"
  }
}

# Attach the data volume to the EC2 instance
resource "aws_volume_attachment" "qdrant_data_attach" {
  device_name                    = "/dev/xvdf"
  volume_id                      = aws_ebs_volume.qdrant_data.id
  instance_id                    = aws_instance.qdrant.id
  stop_instance_before_detaching = true
}

# ------------------------------------------------------------------------------
# Elastic IP — Stable public IP that never changes
# ------------------------------------------------------------------------------

resource "aws_eip" "qdrant_eip" {
  count    = var.enable_elastic_ip ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.qdrant.id

  depends_on = [aws_instance.qdrant]

  tags = {
    Name = "${var.project_name}-eip"
  }
}

# ------------------------------------------------------------------------------
# CloudWatch Alarms — Basic health monitoring
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count               = var.enable_cloudwatch ? 1 : 0
  alarm_name          = "${var.project_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU utilization above 80% for 4 minutes"

  dimensions = {
    InstanceId = aws_instance.qdrant.id
  }

  tags = {
    Name = "${var.project_name}-cpu-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "status_check" {
  count               = var.enable_cloudwatch ? 1 : 0
  alarm_name          = "${var.project_name}-status-check"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "EC2 status check failed"

  dimensions = {
    InstanceId = aws_instance.qdrant.id
  }

  tags = {
    Name = "${var.project_name}-status-alarm"
  }
}
