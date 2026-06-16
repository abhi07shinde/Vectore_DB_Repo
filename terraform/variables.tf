variable "aws_region" {
  default = "eu-central-1"  # ← Change this from ap-south-1
}

variable "ssh_key_name" {
  description = "TCS_YODA_DSO_AI_Vector_DB"
  type        = string
}

variable "qdrant_api_key" {
  description = "eKMUATTm5JJtifdrrH3OTBCI1qPjVvzfF6fX9e90"
  type        = string
  sensitive   = true
}
