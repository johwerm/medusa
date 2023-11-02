resource "aws_cloudwatch_log_group" "medusa" {
  name              = "medusa-log-group"
  skip_destroy      = false
  retention_in_days = 30

  tags = {
    Environment = "production"
    Application = "medusa"
  }
}