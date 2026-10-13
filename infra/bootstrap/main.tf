# Bootstrap: creates the S3 bucket that stores Terraform's "memory" (state)
# for the platform. Run this ONCE, before infra/platform.
#
# This folder keeps its own state locally (terraform.tfstate here, git-ignored)
# because the remote-state bucket cannot store its own state before it exists.
#
#   cd infra/bootstrap
#   terraform init
#   terraform apply

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "region" {
  description = "AWS region for all lab resources"
  type        = string
  default     = "eu-west-2"
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "supportflow"
      Environment = "lab"
      ManagedBy   = "terraform"
      Component   = "bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

# Bucket names must be unique across ALL of AWS, so we add the account ID.
resource "aws_s3_bucket" "tfstate" {
  bucket = "supportflow-tfstate-${data.aws_caller_identity.current.account_id}"

  # Lab setting: lets "terraform destroy" remove the bucket even if it
  # still holds old state versions. Teardown runbook: destroy platform first.
  force_destroy = true
}

# Keep every old version of the state file (lets us recover from mistakes).
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Old state versions are kept 90 days (enough to recover from mistakes).
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# Encrypt state at rest. State can contain sensitive values.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Nobody on the internet can read the state.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Refuse any connection that is not encrypted (HTTPS only).
resource "aws_s3_bucket_policy" "tfstate_tls_only" {
  bucket = aws_s3_bucket.tfstate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

output "state_bucket" {
  description = "Use this in: terraform init -backend-config=\"bucket=...\""
  value       = aws_s3_bucket.tfstate.bucket
}
