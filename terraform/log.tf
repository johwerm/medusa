resource "aws_cloudwatch_log_group" "medusa_backend_redis" {
  name              = "medusa-backend-redis-log-group"
  skip_destroy      = false
  retention_in_days = 30

  tags = {
    Environment = "production"
    Application = "medusa"
  }
}

resource "aws_cloudwatch_log_group" "medusa_backend" {
  name              = "medusa-backend-log-group"
  skip_destroy      = false
  retention_in_days = 30

  tags = {
    Environment = "production"
    Application = "medusa"
  }
}