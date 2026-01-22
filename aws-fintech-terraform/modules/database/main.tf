variable "project_name" {}
variable "environment" {}
variable "vpc_id" {}
variable "private_data_subnets" { type = list(string) }
variable "app_sg_id" {}

# === Security Groups ===

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Security Group for RDS"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.app_sg_id]
  }

  tags = { Name = "${var.project_name}-db-sg" }
}

resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis-sg"
  description = "Security Group for Redis"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.app_sg_id]
  }

  tags = { Name = "${var.project_name}-redis-sg" }
}

# === RDS PostgreSQL (Standard, not Aurora) ===
# Aurora has no perpetual free tier. db.t3.micro Standard is free tier eligible.

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = var.private_data_subnets
  tags       = { Name = "${var.project_name}-db-subnets" }
}

resource "random_password" "db_pass" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "db_creds" {
  name       = "${var.project_name}/db-credentials"
  recovery_window_in_days = 0 
}

resource "aws_secretsmanager_secret_version" "db_creds" {
  secret_id     = aws_secretsmanager_secret.db_creds.id
  secret_string = jsonencode({
    username = "fintechadmin"
    password = random_password.db_pass.result
    engine   = "postgres"
    port     = 5432
    dbname   = "fintech"
  })
}

 resource "aws_db_instance" "main" {
  identifier             = "${var.project_name}-db"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "16.3" # Updated to supported version
  username               = "fintechadmin"
  password               = random_password.db_pass.result
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  db_name                = "fintech"
  publicly_accessible    = false
  skip_final_snapshot    = true
  multi_az               = false # Single AZ for free tier
}

# === Redis (Single Node) ===

resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project_name}-redis-subnets"
  subnet_ids = var.private_data_subnets
}

resource "aws_elasticache_cluster" "main" {
  cluster_id           = "${var.project_name}-redis"
  engine               = "redis"
  node_type            = "cache.t3.micro" # Updated for Redis 7 support
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.redis.id]
}

# === DynamoDB ===

resource "aws_dynamodb_table" "sessions" {
  name         = "${var.project_name}-sessions"
  billing_mode = "PROVISIONED"
  read_capacity  = 5 # Within 25 free units
  write_capacity = 5
  hash_key       = "userId"
  range_key      = "sessionId"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "sessionId"
    type = "S"
  }

  # Removing KMS dependency to save $1
}

output "db_endpoint" { value = aws_db_instance.main.endpoint }
