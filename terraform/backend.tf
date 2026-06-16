terraform {
  backend "s3" {
    bucket  = "REPLACE_WITH_YOUR_BUCKET_NAME"
    key     = "qdrant/terraform.tfstate"
    region  = "eu-central-1"  # ← Change this from ap-south-1
    encrypt = true
  }
}
