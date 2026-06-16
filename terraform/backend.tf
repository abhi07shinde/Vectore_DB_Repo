terraform {
  backend "s3" {
    bucket  = "qdarant-code"
    key     = "qdrant/terraform.tfstate"
    region  = "eu-central-1"
    encrypt = true
  }
}
