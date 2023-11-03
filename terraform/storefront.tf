# resource "aws_ecr_repository" "medusa_storefront" {
#   name                 = "medusa-storefront"
#   image_tag_mutability = "MUTABLE"

#   image_scanning_configuration {
#     scan_on_push = true
#   }
# }

# resource "aws_ecr_lifecycle_policy" "medusa_storefront" {
#   repository = aws_ecr_repository.medusa_storefront.name

#   policy = <<EOF
# {
#     "rules": [
#         {
#             "rulePriority": 1,
#             "description": "Keep last 10 images",
#             "selection": {
#                 "tagStatus": "tagged",
#                 "tagPrefixList": ["v"],
#                 "countType": "imageCountMoreThan",
#                 "countNumber": 10
#             },
#             "action": {
#                 "type": "expire"
#             }
#         }
#     ]
# }
# EOF
# }

# locals {
#   environment_vars = {
#     NPM_USE_PRODUCTION = "false"
#   }
# }

# resource "aws_ecs_task_definition" "medusa_storefront" {
#   family             = "medusa-storefront-td"
#   network_mode       = "awsvpc"
#   execution_role_arn = aws_iam_role.ecs_task_execution.arn
#   runtime_platform {
#     operating_system_family = "LINUX"
#     cpu_architecture        = "X86_64"
#   }
#   container_definitions = jsonencode([
#     {
#       name      = "storefront"
#       image     = "${aws_ecr_repository.medusa_storefront.repository_url}:latest"
#       cpu       = 500
#       memory    = 100
#       essential = true
#       portMappings = [
#         {
#           containerPort = 8000
#           hostPort      = 8000
#           protocol      = "tcp"
#         }
#       ]
#       environment = [for k, v in local.environment_vars : {name = k, value = v}]
#       healthCheck = {
#         command: [ "CMD-SHELL", "wget http://localhost:80 || exit 1" ]
#         interval: 15
#         retries: 3
#         timeout: 5
#       }
#       logConfiguration = {
#         logDriver = "awslogs"
#         options = {
#           awslogs-group = aws_cloudwatch_log_group.medusa.name
#           awslogs-region = var.aws_region
#           awslogs-stream-prefix = "medusa"
#         }
#       }
#     }
#   ])
# }

# resource "aws_ecs_service" "medusa_storefront" {
#   name                               = "medusa-storefront-svc"
#   cluster                            = aws_ecs_cluster.medusa.id
#   task_definition                    = aws_ecs_task_definition.medusa_storefront.arn
#   desired_count                      = 2
#   deployment_minimum_healthy_percent = 100
#   deployment_maximum_percent         = 200

#   network_configuration {
#     subnets         = [for subnet in aws_subnet.medusa_public_subnet : subnet.id]
#     security_groups = [aws_security_group.medusa_web_sg.id]
#   }

#   force_new_deployment = true
#   placement_constraints {
#     type = "distinctInstance"
#   }

#   triggers = {
#     redeployment = true
#   }

#   capacity_provider_strategy {
#     capacity_provider = aws_ecs_capacity_provider.medusa_ecs_cluster.name
#     weight            = 100
#   }

#   load_balancer {
#     target_group_arn = aws_lb_target_group.medusa_storefront.arn
#     container_name   = "storefront"
#     container_port   = 8000
#   }

#   depends_on = [aws_autoscaling_group.medusa_ecs_cluster]

#   lifecycle {
#     ignore_changes = [desired_count]
#   }
# }

# resource "aws_lb" "medusa_storefront" {
#   name               = "medusa-storefront-alb"
#   internal           = false
#   load_balancer_type = "application"
#   security_groups    = [aws_security_group.medusa_web_sg.id]
#   subnets            = [for subnet in aws_subnet.medusa_public_subnet : subnet.id]

#   tags = {
#     Name = "medusa-storefront-alb"
#   }
# }

# resource "aws_lb_target_group" "medusa_storefront" {
#   name        = "medusa-storefront-target-group"
#   port        = 80
#   protocol    = "HTTP"
#   target_type = "ip"
#   vpc_id      = aws_vpc.medusa.id

#   health_check {
#     path                = "/health"
#     interval            = 30
#     healthy_threshold   = 2
#     unhealthy_threshold = 3
#   }
# }

# resource "aws_lb_listener" "medusa_storefront" {
#   load_balancer_arn = aws_lb.medusa_storefront.arn
#   port              = 80
#   protocol          = "HTTP"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.medusa_storefront.arn
#   }
# }