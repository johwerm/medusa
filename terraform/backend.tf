### Postgres ###
resource "aws_db_instance" "medusa_backend" {
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

### Redis ###
resource "aws_elasticache_subnet_group" "medusa_backend" {
  name       = "medusa-elasticcache-sg"
  subnet_ids = [for subnet in aws_subnet.medusa_private_subnet : subnet.id]
}

resource "aws_elasticache_replication_group" "medusa_backend_redis_cluster" {
  replication_group_id       = "medusa-backend-redis-cluster"
  description                = "Redis Cluster"
  node_type                  = "cache.t3.micro"

  engine                     = "redis"
  port                       = 6379
  #parameter_group_name       = "default.redis7.cluster.on"
  parameter_group_name       = "default.redis7"

  transit_encryption_enabled = true
  auth_token                 = random_password.medusa_backend_redis_password.result

  automatic_failover_enabled = true
  apply_immediately          = true
  
  num_cache_clusters         = 2
  #num_node_groups            = 2
  #replicas_per_node_group    = 1

  subnet_group_name          = aws_elasticache_subnet_group.medusa_backend.name
  security_group_ids         = [aws_security_group.medusa_db_sg.id]

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.medusa_backend_redis.name
    destination_type = "cloudwatch-logs"
    log_format       = "text"
    log_type         = "slow-log"
  }
}

resource "random_password" "medusa_backend_redis_password" {
  length = 40
  special = false
}

### Repository ###
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

### App ###
resource "random_password" "medusa_backend_jwt_secret" {
  length = 40
  special = false
}

resource "random_password" "medusa_backend_cookie_secret" {
  length = 40
  special = false
}

locals {
  environment_vars = {
    NPM_USE_PRODUCTION = "true"
    JWT_SECRET = random_password.medusa_backend_jwt_secret.result
    COOKIE_SECRET = random_password.medusa_backend_cookie_secret.result
    DATABASE_URL = "postgres://${local.conf.postgresql.user}:${local.conf.postgresql.password}@${aws_db_instance.medusa_backend.endpoint}/${local.conf.postgresql.db_name}?sslmode=verify-full"
    REDIS_URL = "rediss://:${random_password.medusa_backend_redis_password.result}@${aws_elasticache_replication_group.medusa_backend_redis_cluster.primary_endpoint_address}:${aws_elasticache_replication_group.medusa_backend_redis_cluster.port}"
#    REDIS_URL = "rediss://:${random_password.medusa_backend_redis_password.result}@${aws_elasticache_replication_group.medusa_backend_redis_cluster.configuration_endpoint_address}:${aws_elasticache_replication_group.medusa_backend_redis_cluster.port}"
  }
}

resource "aws_ecs_task_definition" "medusa_backend" {
  family             = "medusa-backend-td"
  network_mode       = "awsvpc"
  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = "${aws_ecr_repository.medusa_backend.repository_url}:latest"
      cpu       = 512
      memory    = 1024
      essential = true
      portMappings = [
        {
          containerPort = 9000
          hostPort      = 9000
          protocol      = "tcp"
        }
      ]
      environment = [for k, v in local.environment_vars : {name = k, value = v}]
      # healthCheck = {
      #   command: [ "CMD-SHELL", "wget http://localhost:9000/health || exit 1" ]
      #   interval: 30
      #   retries: 3
      #   startPeriod: 120
      #   timeout: 5
      # }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group = aws_cloudwatch_log_group.medusa_backend.name
          awslogs-region = var.aws_region
          awslogs-stream-prefix = "medusa"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "medusa_backend" {
  name                               = "medusa-backend-svc"
  cluster                            = aws_ecs_cluster.medusa.id
  task_definition                    = aws_ecs_task_definition.medusa_backend.arn
  desired_count                      = 2
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets         = [for subnet in aws_subnet.medusa_public_subnet : subnet.id]
    security_groups = [aws_security_group.medusa_web_sg.id]
  }

  force_new_deployment = true
  placement_constraints {
    type = "distinctInstance"
  }

  triggers = {
    redeployment = true
  }

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.medusa_ecs_cluster.name
    weight            = 100
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.medusa_backend.arn
    container_name   = "backend"
    container_port   = 9000
  }

  depends_on = [aws_autoscaling_group.medusa_ecs_cluster]

  lifecycle {
    ignore_changes = [desired_count]
  }
}

resource "aws_lb" "medusa_backend" {
  name               = "medusa-backend-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.medusa_web_sg.id]
  subnets            = [for subnet in aws_subnet.medusa_public_subnet : subnet.id]

  tags = {
    Name = "medusa-backend-alb"
  }
}

resource "aws_lb_target_group" "medusa_backend" {
  name        = "medusa-backend-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.medusa.id

  health_check {
    path                = "/health"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 4
  }
}

resource "aws_lb_listener" "medusa_backend" {
  load_balancer_arn = aws_lb.medusa_backend.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.medusa_backend.arn
  }
}