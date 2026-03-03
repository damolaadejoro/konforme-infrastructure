terraform {
  backend "s3" {
    bucket         = "konforme-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "konforme-terraform-locks"
    encrypt        = true
  }
}
