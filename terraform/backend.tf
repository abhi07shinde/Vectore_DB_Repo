# =============================================================================
# backend.tf — S3 Remote State Configuration
# =============================================================================
# IMPORTANT: Replace the bucket name with your actual S3 bucket name
# The S3 bucket must already exist before running terraform init
# Create it manually once:
#   aws s3 mb s3://YOUR-BUCKET-NAME --region ap-south-1
#   aws s3api put-bucket-versioning \
#     --bucket YOUR-BUCKET-NAME \
#     --versioning-configuration Status=Enabled
# =============================================================================

terraform {
  backend "s3" {
    # This value is injected by GitHub Actions via -backend-config
    # See terraform.yml for how this is passed
    bucket  = "REPLACE_WITH_YOUR_BUCKET_NAME"
    key     = "qdrant/terraform.tfstate"
    region  = "ap-south-1"
    encrypt = true

    # Optional: DynamoDB table for state locking (prevents concurrent applies)
    # dynamodb_table = "terraform-state-lock"
  }
}
