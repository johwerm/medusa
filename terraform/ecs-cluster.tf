data "aws_key_pair" "medusa_ec2" {
  key_name   = "medusa-ec2"
}

# resource "aws_key_pair" "medusa_ec2" {
#   key_name   = "medusa-ec2"
#   public_key = local.conf.ec2.public_key
# }

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
#docker run -d -p 80:80 414252688381.dkr.ecr.eu-north-1.amazonaws.com/medusa-backend:latest
resource "aws_launch_template" "medusa_ecs_cluster" {
  name_prefix   = "ecs-template-"
  image_id      = "ami-03b8fad9f2144de61" # Amazon ECS-optimized Amazon Linux 2023 AMI
  instance_type = "t3.small"

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

  user_data = base64encode(templatefile("${path.module}/ecs.sh.tftpl", { cluster_name = aws_ecs_cluster.medusa.name }))
}

resource "aws_autoscaling_group" "medusa_ecs_cluster" {
  name                = "medusa-ecs-cluster-asg"
  vpc_zone_identifier = [for subnet in aws_subnet.medusa_public_subnet : subnet.id]
  max_size            = 2
  min_size            = 1

  launch_template {
    id      = aws_launch_template.medusa_ecs_cluster.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

resource "aws_ecs_cluster" "medusa" {
  name = "medusa-ecs-cluster"
}

resource "aws_ecs_capacity_provider" "medusa_ecs_cluster" {
  name = "medusa-ecs-cluster-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.medusa_ecs_cluster.arn

    managed_scaling {
      maximum_scaling_step_size = 1000
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 2
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "medusa_ecs_cluster" {
  cluster_name = aws_ecs_cluster.medusa.name

  capacity_providers = [aws_ecs_capacity_provider.medusa_ecs_cluster.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.medusa_ecs_cluster.name
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