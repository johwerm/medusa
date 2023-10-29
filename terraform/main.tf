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

variable "vpc_cidr_block" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_count" {
  description = "Number of subnets"
  type        = map(number)
  default = {
    public  = 2,
    private = 2
  }
}

variable "public_subnet_cidr_blocks" {
  description = "Available CIDR blocks for public subnets"
  type        = list(string)
  default = [
    "10.0.1.0/24",
    "10.0.2.0/24",
    "10.0.3.0/24",
    "10.0.4.0/24"
  ]
}

// This variable contains the CIDR blocks for
// the public subnet. I have only included 4 
// for this tutorial, but if you need more you
// would add them here
variable "private_subnet_cidr_blocks" {
  description = "Available CIDR blocks for private subnets"
  type        = list(string)
  default = [
    "10.0.101.0/24",
    "10.0.102.0/24",
    "10.0.103.0/24",
    "10.0.104.0/24",
  ]
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

data "aws_availability_zones" "medusa" {
  state = "available"
}

resource "aws_vpc" "medusa" {

  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  tags = {
    Name = "medusa"
  }
}

resource "aws_internet_gateway" "medusa" {
  vpc_id = aws_vpc.medusa.id
  tags = {
    Name = "medusa"
  }
}

// Create a group of public subnets based on the variable subnet_count.public
resource "aws_subnet" "medusa_public_subnet" {
  count             = var.subnet_count.public
  vpc_id            = aws_vpc.medusa.id
  cidr_block        = var.public_subnet_cidr_blocks[count.index]
  availability_zone = data.aws_availability_zones.medusa.names[count.index]
  tags = {
    Name = "medusa_public_subnet_${count.index}"
  }
}

// Create a group of private subnets based on the variable subnet_count.private
resource "aws_subnet" "medusa_private_subnet" {
  count             = var.subnet_count.private
  vpc_id            = aws_vpc.medusa.id
  cidr_block        = var.private_subnet_cidr_blocks[count.index]
  availability_zone = data.aws_availability_zones.medusa.names[count.index]
  tags = {
    Name = "medusa_private_subnet_${count.index}"
  }
}

resource "aws_route_table" "medusa_public_rt" {
  vpc_id = aws_vpc.medusa.id

  // Since this is the public route table, it will need
  // access to the internet. So we are adding a route with
  // a destination of 0.0.0.0/0 and targeting the Internet 	 
  // Gateway "tutorial_igw"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.medusa.id
  }
}

resource "aws_route_table_association" "public" {
  count          = var.subnet_count.public
  route_table_id = aws_route_table.medusa_public_rt.id
  subnet_id      = 	aws_subnet.medusa_public_subnet[count.index].id
}

resource "aws_route_table" "medusa_private_rt" {
  vpc_id = aws_vpc.medusa.id
}

resource "aws_route_table_association" "private" {
  count          = var.subnet_count.private
  route_table_id = aws_route_table.medusa_private_rt.id
  subnet_id      = aws_subnet.medusa_private_subnet[count.index].id
}

resource "aws_security_group" "medusa_web_sg" {
  name        = "medusa_web_sg"
  description = "Security group for medusa web servers"
  vpc_id      = aws_vpc.medusa.id

  ingress {
    description = "Allow all traffic through HTTP"
    from_port   = "80"
    to_port     = "8080"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH from my computer"
    from_port   = "22"
    to_port     = "22"
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "medusa_web_sg"
  }
}

resource "aws_security_group" "medusa_db_sg" {
  name        = "medusa_db_sg"
  description = "Security group for medusa databases"
  vpc_id      = aws_vpc.medusa.id

  // The third requirement was "RDS should be on a private subnet and 	
  // inaccessible via the internet." To accomplish that, we will 
  // not add any inbound or outbound rules for outside traffic.
  
  // The fourth and finally requirement was "Only the EC2 instances 
  // should be able to communicate with RDS." So we will create an
  // inbound rule that allows traffic from the EC2 security group
  // through TCP port 3306, which is the port that MySQL 
  // communicates through
  ingress {
    description     = "Allow PostgreSQL traffic from only the web sg"
    from_port       = "5432"
    to_port         = "5432"
    protocol        = "tcp"
    security_groups = [aws_security_group.medusa_web_sg.id]
  }

  tags = {
    Name = "medusa_db_sg"
  }
}

resource "aws_db_subnet_group" "medusa_db_subnet_group" {
  name        = "medusa_db_subnet_group"
  description = "DB subnet group for medusa"
  subnet_ids  = [for subnet in aws_subnet.medusa_private_subnet : subnet.id]
}


# // Create an EC2 instance named "tutorial_web"
# resource "aws_instance" "tutorial_web" {
#   // count is the number of instance we want
#   // since the variable settings.web_app.cont is set to 1, we will only get 1 EC2
#   count                  = var.settings.web_app.count
  
#   // Here we need to select the ami for the EC2. We are going to use the
#   // ami data object we created called ubuntu, which is grabbing the latest
#   // Ubuntu 20.04 ami
#   ami                    = data.aws_ami.ubuntu.id
  
#   // This is the instance type of the EC2 instance. The variable
#   // settings.web_app.instance_type is set to "t2.micro"
#   instance_type          = var.settings.web_app.instance_type
  
#   // The subnet ID for the EC2 instance. Since "tutorial_public_subnet" is a list
#   // of public subnets, we want to grab the element based on the count variable.
#   // Since count is 1, we will be grabbing the first subnet in  	
#   // "tutorial_public_subnet" and putting the EC2 instance in there
#   subnet_id              = aws_subnet.tutorial_public_subnet[count.index].id
  
#   // The key pair to connect to the EC2 instance. We are using the "tutorial_kp" key 
#   // pair that we created
#   key_name               = aws_key_pair.tutorial_kp.key_name
  
#   // The security groups of the EC2 instance. This takes a list, however we only
#   // have 1 security group for the EC2 instances.
#   vpc_security_group_ids = [aws_security_group.tutorial_web_sg.id]

#   // We are tagging the EC2 instance with the name "tutorial_db_" followed by
#   // the count index
#   tags = {
#     Name = "tutorial_web_${count.index}"
#   }
# }

# // Create an Elastic IP named "tutorial_web_eip" for each
# // EC2 instance
# resource "aws_eip" "tutorial_web_eip" {
# 	// count is the number of Elastic IPs to create. It is
# 	// being set to the variable settings.web_app.count which
# 	// refers to the number of EC2 instances. We want an
# 	// Elastic IP for every EC2 instance
#   count    = var.settings.web_app.count

# 	// The EC2 instance. Since tutorial_web is a list of 
# 	// EC2 instances, we need to grab the instance by the 
# 	// count index. Since the count is set to 1, it is
# 	// going to grab the first and only EC2 instance
#   instance = aws_instance.tutorial_web[count.index].id

# 	// We want the Elastic IP to be in the VPC
#   vpc      = true

# 	// Here we are tagging the Elastic IP with the name
# 	// "tutorial_web_eip_" followed by the count index
#   tags = {
#     Name = "tutorial_web_eip_${count.index}"
#   }
# }

resource "aws_db_instance" "medusa" {
  allocated_storage      = 10
  db_name                = local.conf.postgresql.db_name
  engine                 = "postgres"
  engine_version         = "15.3"
  instance_class         = "db.t3.micro"
  username               = local.conf.postgresql.user
  password               = local.conf.postgresql.password
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.medusa_db_subnet_group.id
  vpc_security_group_ids = [aws_security_group.medusa_db_sg.id]
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

resource "random_password" "medusa_server_jwt_secret" {
  length = 40
  special = false
}

resource "random_password" "medusa_server_cookie_secret" {
  length = 40
  special = false
}

locals {
  environment_vars = {
    NPM_USE_PRODUCTION = false
    JWT_SECRET = random_password.medusa_server_jwt_secret.result
    COOKIE_SECRET = random_password.medusa_server_cookie_secret.result
    DATABASE_URL = "postgres://${local.conf.postgresql.user}:${local.conf.postgresql.password}@${aws_db_instance.medusa.endpoint}/${local.conf.postgresql.db_name}"
  }
}

resource "aws_elastic_beanstalk_environment" "medusa" {
  name                = "medusa"
  application         = aws_elastic_beanstalk_application.medusa.name
  solution_stack_name = "64bit Amazon Linux 2023 v6.0.2 running Node.js 18"

  # Application
  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = aws_vpc.medusa.id
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
    value     = join(",", [for subnet in aws_subnet.medusa_private_subnet : subnet.id])
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
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = join(",", sort([aws_security_group.medusa_web_sg.id]))
    resource  = ""
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

  # Environment Variables
  dynamic "setting" {
    for_each = local.environment_vars
    content {
      namespace = "aws:elasticbeanstalk:application:environment"
      name      = setting.key
      value     = setting.value
    }
  }

  # Database
  # setting {
  #   namespace = "aws:rds:dbinstance"
  #   name      = "DBAllocatedStorage"
  #   value     = "2"
  # }
  # setting {
  #   namespace = "aws:rds:dbinstance"
  #   name      = "DBDeletionPolicy"
  #   value     = "Delete"
  # }
  # setting {
  #   namespace = "aws:rds:dbinstance"
  #   name      = "HasCoupledDatabase"
  #   value     = "true"
  # }
  # setting {
  #   namespace = "aws:rds:dbinstance"
  #   name      = "DBEngine"
  #   value     = "postgres"
  # }
  # setting {
  #   namespace = "aws:rds:dbinstance"
  #   name      = "DBEngineVersion"
  #   value     = "15.3"
  # }
  # setting {
  #   namespace = "aws:rds:dbinstance"
  #   name      = "DBInstanceClass"
  #   value     = "db.t3.micro"
  # }
  # setting {
  #   namespace = "aws:rds:dbinstance"
  #   name      = "DBName"
  #   value     = local.conf.postgresql.db_name
  # }
  # setting {
  #   namespace = "aws:rds:dbinstance"
  #   name      = "DBPassword"
  #   value     = local.conf.postgresql.password
  # }
  # setting {
  #   namespace = "aws:rds:dbinstance"
  #   name      = "DBUser"
  #   value     = local.conf.postgresql.user
  # }
}


# Pipeline
resource "aws_kms_key" "medusa-pipeline" {
  description             = "Medusa Pipeline"
  deletion_window_in_days = 10
}

resource "aws_codestarconnections_connection" "medusa" {
  name          = "github-medusa"
  provider_type = "GitHub"
}

resource "aws_codepipeline" "medusa" {
  name     = "medusa-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.medusa_pipeline.bucket
    type     = "S3"

    encryption_key {
      id   = data.aws_kms_key.medusa-pipeline.arn
      type = "KMS"
    }
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.medusa.arn
        FullRepositoryId = "johwerm/medusa"
        BranchName       = "main"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name = "Deploy"
      category = "Deploy"
      owner = "AWS"
      provider = "ElasticBeanstalk"
      input_artifacts = ["build"]
      version = "1"

      configuration {
        ApplicationName = "${aws_elastic_beanstalk_application.medusa.name}"
        EnvironmentName = "${aws_elastic_beanstalk_environment.medusa.name}"
      }
    }
  }

}

resource "aws_s3_bucket" "medusa_codepipeline" {
  bucket = "medusa-codepipeline-wxnet-se"
}

resource "aws_s3_bucket_acl" "medusa_codepipeline" {
  bucket = aws_s3_bucket.medusa_codepipeline.id
  acl    = "private"
}

data "aws_iam_policy_document" "medusa_codepipeline_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "medusa_codepipeline" {
  name               = "medusa-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.medusa_codepipeline_assume_role.json
}

data "aws_iam_policy_document" "medusa_codepipeline" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObjectAcl",
      "s3:PutObject",
    ]

    resources = [
      aws_s3_bucket.medusa_codepipeline.arn,
      "${aws_s3_bucket.medusa_codepipeline.arn}/*"
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["codestar-connections:UseConnection"]
    resources = [aws_codestarconnections_connection.medusa_github.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codepipeline" {
  name   = "medusa-codepipeline-policy"
  role   = aws_iam_role.medusa_codepipeline.id
  policy = data.aws_iam_policy_document.medusa_codepipeline.json
}
