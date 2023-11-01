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

data "aws_iam_user" "medusa" {
  user_name = "medusa"
}

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
  cidr_block        = cidrsubnet(aws_vpc.medusa.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.medusa.names[count.index]
  tags = {
    Name = "medusa_public_subnet_${count.index}"
  }
}

// Create a group of private subnets based on the variable subnet_count.private
resource "aws_subnet" "medusa_private_subnet" {
  count             = var.subnet_count.private
  vpc_id            = aws_vpc.medusa.id
  cidr_block        = cidrsubnet(aws_vpc.medusa.cidr_block, 8, count.index + 100)
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
  subnet_id      = aws_subnet.medusa_public_subnet[count.index].id
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
  name        = "medusa-web-sg"
  description = "Security group for medusa web servers"
  vpc_id      = aws_vpc.medusa.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    self        = "false"
    cidr_blocks = ["0.0.0.0/0"]
    description = "any"
  }

  # ingress {
  #   description = "Allow all traffic through HTTP"
  #   from_port   = "80"
  #   to_port     = "80"
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  # ingress {
  #   description = "Allow all traffic through HTTP"
  #   from_port   = "8080"
  #   to_port     = "8080"
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  # ingress {
  #   description = "Allow SSH from my computer"
  #   from_port   = "22"
  #   to_port     = "22"
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  #   #cidr_blocks = ["${var.my_ip}/32"]
  # }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "medusa-web-sg"
  }
}

resource "aws_security_group" "medusa_db_sg" {
  name        = "medusa-db-sg"
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
    Name = "medusa-db-sg"
  }
}

resource "aws_db_subnet_group" "medusa_db_subnet_group" {
  name        = "medusa_db_subnet_group"
  description = "DB subnet group for medusa"
  subnet_ids  = [for subnet in aws_subnet.medusa_private_subnet : subnet.id]
}

# resource "aws_key_pair" "medusa_ec2" {
#   key_name   = "medusa-ec2"
#   public_key = local.conf.ec2.public_key
# }

data "aws_key_pair" "medusa_ec2" {
  key_name   = "medusa-ec2"
}

resource "aws_iam_role" "ecs_instance" {
    name = "ecs-instance-role"
    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "ecs-instance-profile"
  role = aws_iam_role.ecs_instance.name
}

resource "aws_launch_template" "medusa_ecs" {
  name_prefix   = "ecs-template-"
  image_id      = "ami-03b8fad9f2144de61" # Amazon ECS-optimized Amazon Linux 2023 AMI
  instance_type = "t3.micro"

  update_default_version = true
  key_name               = data.aws_key_pair.medusa_ec2.key_name
  vpc_security_group_ids = [aws_security_group.medusa_web_sg.id]
  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance.name
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30
      volume_type = "gp2"
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "ecs-instance"
    }
  }

  user_data = base64encode(templatefile("${path.module}/ecs.sh.tftpl", { cluster_name = aws_ecs_cluster.medusa_ecs.name }))
  #user_data = filebase64("${path.module}/ecs.sh")
}

resource "aws_autoscaling_group" "medusa_ecs" {
  name                = "medusa-ecs-asg"
  vpc_zone_identifier = [for subnet in aws_subnet.medusa_public_subnet : subnet.id]
  max_size            = 3
  min_size            = 1

  launch_template {
    id      = aws_launch_template.medusa_ecs.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

resource "aws_lb" "medusa_ecs" {
  name               = "medusa-ecs-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.medusa_web_sg.id]
  subnets            = [for subnet in aws_subnet.medusa_public_subnet : subnet.id]

  tags = {
    Name = "ecs-alb"
  }
}

resource "aws_lb_target_group" "medusa_ecs" {
  name        = "medusa-ecs-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.medusa.id

  health_check {
    path = "/"
  }
}

resource "aws_lb_listener" "medusa_ecs" {
  load_balancer_arn = aws_lb.medusa_ecs.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.medusa_ecs.arn
  }
}

resource "aws_ecs_cluster" "medusa_ecs" {
  name = "medusa-ecs-cluster"
}

resource "aws_ecs_capacity_provider" "medusa_ecs" {
  name = "medusa-ecs-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.medusa_ecs.arn

    managed_scaling {
      maximum_scaling_step_size = 1000
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 2
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "medusa_ecs" {
  cluster_name = aws_ecs_cluster.medusa_ecs.name

  capacity_providers = [aws_ecs_capacity_provider.medusa_ecs.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.medusa_ecs.name
  }
}

resource "aws_ecr_repository" "medusa_backend" {
  name                 = "medusa-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "medusa_backend" {
  repository = aws_ecr_repository.medusa_backend.name

  policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep last 10 images",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["v"],
                "countType": "imageCountMoreThan",
                "countNumber": 10
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}

resource "random_password" "medusa_server_jwt_secret" {
  length = 40
  special = false
}

resource "random_password" "medusa_server_cookie_secret" {
  length = 40
  special = false
}

resource "aws_db_instance" "medusa" {
  identifier             = "medusa"
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

locals {
  environment_vars = {
    NPM_USE_PRODUCTION = "false"
    JWT_SECRET = random_password.medusa_server_jwt_secret.result
    COOKIE_SECRET = random_password.medusa_server_cookie_secret.result
    DATABASE_URL = "postgres://${local.conf.postgresql.user}:${local.conf.postgresql.password}@${aws_db_instance.medusa.endpoint}/${local.conf.postgresql.db_name}"
  }
}

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution" {
  name = "ecs-task-execution-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "medusa_ecs_backend" {
  family             = "medusa-ecs-backend"
  network_mode       = "awsvpc"
  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  cpu                = 256
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = "${aws_ecr_repository.medusa_backend.repository_url}:latest"
      cpu       = 256
      memory    = 256
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
      environment = [for k, v in local.environment_vars : {name = k, value = v}]
    }
  ])
}

resource "aws_ecs_service" "medusa_ecs_backend" {
  name            = "medusa-ecs-backend"
  cluster         = aws_ecs_cluster.medusa_ecs.id
  task_definition = aws_ecs_task_definition.medusa_ecs_backend.arn
  desired_count   = 2

  network_configuration {
    subnets         = [for subnet in aws_subnet.medusa_public_subnet : subnet.id]
    security_groups = [aws_security_group.medusa_web_sg.id]
  }

  force_new_deployment = true
  placement_constraints {
    type = "distinctInstance"
  }

  triggers = {
    redeployment = "${timestamp()}"
  }

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.medusa_ecs.name
    weight            = 100
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.medusa_ecs.arn
    container_name   = "backend"
    container_port   = 80
  }

  depends_on = [aws_autoscaling_group.medusa_ecs]
}


