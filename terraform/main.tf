terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = ">=4.64.0"
    }
  }
  
  backend "s3" {
    region = "eu-north-1"
    bucket = "terraform-medusa-state-wxnet-se"
    key    = "terraform.tfstate"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
#  access_key = var.aws_access_key_id
#  secret_key = var.aws_secret_access_key
}

# Secrets
data "aws_secretsmanager_secret_version" "creds" {
  secret_id = "terraform-medusa/credentials"
}

locals {
  conf = jsondecode(data.aws_secretsmanager_secret_version.creds.secret_string)
}

# Variables
variable "aws_region" {
  type    = string
  default = "eu-north-1"
}
