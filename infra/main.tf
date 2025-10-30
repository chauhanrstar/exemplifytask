# Configure Terraform behavior and providers
terraform {
  # S3 backend configuration for state storage
  backend "s3" {
    bucket         = "exemplifi-wp-tfstate"     # Update this to your created bucket name
    key            = "global/terraform.tfstate" # Path within the bucket
    region         = "ap-south-1"               # Match your bucket's region
    dynamodb_table = "exemplifi-wp-tf-lock"     # DynamoDB table for state locking
    encrypt        = true                       # Enable state file encryption
  }

  # Specify required Terraform and provider versions
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

// Configure the AWS Provider and set provider-level default tags
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project = "Exemplifi WebOps"
      Managed = "Terraform"
    }
  }
}
