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

variable "vpc-id" {
  type    = string
  default = "vpc-05e9dfefa452595fc"
}

variable "private-subnets" {
  type    = list(string)
  default = ["subnet-039adc969821f7d22", "subnet-018f7aa749d81be14"]
}

variable "public-subnets" {
  type    = list(string)
  default = ["subnet-0e29be189ffbaa145", "subnet-06eb0c48aab4f36e6"]
}


#############################
#############################

resource "aws_vpc" "medusa" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_elastic_beanstalk_application" "medusa" {
  name        = "medusa"
  description = "medusa"

  appversion_lifecycle {
    service_role          = aws_iam_role.beanstalk_service.arn
    max_count             = 128
    delete_source_from_s3 = true
  }
}

resource "aws_elastic_beanstalk_environment" "medusa" {
  name                = "medusa"
  application         = aws_elastic_beanstalk_application.medusa.name
  solution_stack_name = "64bit Amazon Linux 2023 v6.0.2 running Node.js 18"

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = var.vpc_id
  }
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     =  "aws-elasticbeanstalk-ec2-role"
  }
  setting {
    namespace = "aws:ec2:vpc"
    name      = "AssociatePublicIpAddress"
    value     =  "True"
  }
 
  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", var.public_subnets)
  }
  setting {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name      = "MatcherHTTPCode"
    value     = "200"
  }
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = "t2.micro"
  }
  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBScheme"
    value     = "internet facing"
  }
  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = 1
  }
  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = 2
  }
  setting {
    namespace = "aws:elasticbeanstalk:healthreporting:system"
    name      = "SystemType"
    value     = "enhanced"
  }

  # Database
  setting {
    namespace = "aws:rds:dbinstance"
    name      = "DBAllocatedStorage"
    value     = "2"
  }
  setting {
    namespace = "aws:rds:dbinstance"
    name      = "DBDeletionPolicy"
    value     = "Delete"
  }
  setting {
    namespace = "aws:rds:dbinstance"
    name      = "HasCoupledDatabase"
    value     = "true"
  }
  setting {
    namespace = "aws:rds:dbinstance"
    name      = "DBEngine"
    value     = "postgres"
  }
  setting {
    namespace = "aws:rds:dbinstance"
    name      = "DBEngineVersion"
    value     = "15.3"
  }
  setting {
    namespace = "aws:rds:dbinstance"
    name      = "DBInstanceClass"
    value     = "db.t3.micro"
  }
  setting {
    namespace = "aws:rds:dbinstance"
    name      = "DBPassword"
    value     = data.conf.postgresql.password
  }
  setting {
    namespace = "aws:rds:dbinstance"
    name      = "DBUser"
    value     = data.conf.postgresql.user
  }
}

