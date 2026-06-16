terraform {
  backend "s3" {
    bucket  = "qdarant-code"
    key     = "qdrant/terraform.tfstate"
    region  = "ap-south-1"
    encrypt = true
  }
}
