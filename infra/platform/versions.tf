terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Remote state in the bootstrap bucket, with native S3 locking
  # (use_lockfile). The bucket name is passed at init time:
  #   terraform init -backend-config="bucket=supportflow-tfstate-<ACCOUNT_ID>"
  backend "s3" {
    key          = "platform/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  # Every resource gets these tags, so it's easy to find (and clean up)
  # everything this project created.
  default_tags {
    tags = {
      Project     = "supportflow"
      Environment = "lab"
      Owner       = var.owner
      ManagedBy   = "terraform"
    }
  }
}
