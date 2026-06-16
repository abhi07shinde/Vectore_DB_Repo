# =============================================================================
# variables.tf — All Input Variables
# =============================================================================

# ------------------------------------------------------------------------------
# AWS Configuration
# ------------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-south-1"
}

# ------------------------------------------------------------------------------
# Project Metadata
# ------------------------------------------------------------------------------
variable "project_name" {
  description = "Name of the project — used for tagging and naming resources"
  type        = string
  default     = "qdrant-vector-db"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# ------------------------------------------------------------------------------
# Networking / Security
# ------------------------------------------------------------------------------
variable "team_cidr_blocks" {
  description = <<-EOT
    List of CIDR blocks allowed to access Qdrant API (port 6333).
    For distributed teams with no fixed IP, use ["0.0.0.0/0"].
    For office network, use your office IP range e.g. ["203.x.x.x/24"].
    SECURITY TIP: Restrict this as tightly as possible.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "admin_ssh_cidr_blocks" {
  description = <<-EOT
    List of CIDR blocks allowed SSH access (port 22).
    MUST be restricted to admin IPs only.
    Example: ["203.x.x.x/32", "115.y.y.y/32"]
    Set via GitHub Secret: ADMIN_SSH_CIDR (comma-separated)
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Override this via tfvars or GitHub Secret
}

# ------------------------------------------------------------------------------
# EC2 / Compute
# ------------------------------------------------------------------------------
variable "instance_type" {
  description = "EC2 instance type for Qdrant server"
  type        = string
  default     = "t3.medium"
}

variable "key_pair_name" {
  description = "Name of the existing AWS EC2 key pair for SSH access"
  type        = string
  # No default — must be provided via GitHub Secret SSH_KEY_NAME
}

variable "ami_id" {
  description = <<-EOT
    AMI ID for the EC2 instance.
    Default is Ubuntu 22.04 LTS in ap-south-1.
    Find latest: https://cloud-images.ubuntu.com/locator/ec2/
  EOT
  type        = string
  default     = "ami-0dee22c13ea7a9a67"  # Ubuntu 22.04 LTS ap-south-1 (2024)
}

# ------------------------------------------------------------------------------
# Storage
# ------------------------------------------------------------------------------
variable "root_volume_size" {
  description = "Root EBS volume size in GB (OS + Docker)"
  type        = number
  default     = 20
}

variable "data_volume_size" {
  description = "Qdrant data EBS volume size in GB (40 GB recommended for 50K+ vectors)"
  type        = number
  default     = 40

  validation {
    condition     = var.data_volume_size >= 30 && var.data_volume_size <= 500
    error_message = "Data volume size must be between 30 and 500 GB."
  }
}

variable "data_volume_type" {
  description = "EBS volume type (gp3 recommended for cost + performance)"
  type        = string
  default     = "gp3"
}

# ------------------------------------------------------------------------------
# Qdrant Configuration
# ------------------------------------------------------------------------------
variable "qdrant_api_key" {
  description = <<-EOT
    API key for Qdrant authentication.
    Store as GitHub Secret: QDRANT_API_KEY
    Team members use this in Authorization header: api-key: <value>
  EOT
  type        = string
  sensitive   = true
  # No default — must be provided via GitHub Secret
}

# ------------------------------------------------------------------------------
# Elastic IP
# ------------------------------------------------------------------------------
variable "enable_elastic_ip" {
  description = "Allocate and attach an Elastic IP for a stable endpoint"
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# CloudWatch Monitoring
# ------------------------------------------------------------------------------
variable "enable_cloudwatch" {
  description = "Enable detailed CloudWatch monitoring for the EC2 instance"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}
