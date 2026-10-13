terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "konforme"
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}

# CloudFront certificates must live in us-east-1 (see frontend.tf)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "konforme"
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}
