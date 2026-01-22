variable "project_name" {}
variable "environment" {}
variable "vpc_id" {}
variable "private_data_subnets" { type = list(string) }
variable "app_sg_id" {}
variable "kms_key_id" {}

# === Security Groups ===

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Security Group for Aurora"
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

# === Aurora PostgreSQL ===

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
  kms_key_id = var.kms_key_id
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

resource "aws_rds_cluster" "main" {
  cluster_identifier      = "${var.project_name}-cluster"
  engine                  = "aurora-postgresql"
  engine_version          = "15.4"
  master_username         = "fintechadmin"
  master_password         = random_password.db_pass.result
  database_name           = "fintech"
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  storage_encrypted       = true
  kms_key_id              = var.kms_key_id
  skip_final_snapshot     = true # For demo/dev purposes
  # deletion_protection     = true # Omitted for easy cleanup in demo
  
  serverlessv2_scaling_configuration {
    max_capacity = 2.0
    min_capacity = 0.5
  }
}

resource "aws_rds_cluster_instance" "main" {
  count              = 2
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version
}

# === Redis ===

resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project_name}-redis-subnets"
  subnet_ids = var.private_data_subnets
}

# Removed transit_encryption/auth for simplicity/stability in demo Terraform, 
# typically requires complex logic for auth token in TF providers.
# Keeping it basic: Replication Group in VPC.

resource "aws_elasticache_replication_group" "main" {
  replication_group_id   = "${var.project_name}-redis"
  description            = "Fintech Redis"
  engine                 = "redis"
  node_type              = "cache.t3.micro"
  num_cache_clusters     = 2
  parameter_group_name   = "default.redis7"
  port                   = 6379
  subnet_group_name      = aws_elasticache_subnet_group.main.name
  security_group_ids     = [aws_security_group.redis.id]
  automatic_failover_enabled = true
  multi_az_enabled           = true
}

# === DynamoDB ===

resource "aws_dynamodb_table" "sessions" {
  name         = "${var.project_name}-sessions"
  billing_mode = "PROVISIONED"
  read_capacity  = 5
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

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_id
  }

  lifecycle {
    ignore_changes = [read_capacity, write_capacity] # Ignore changes if AutoScaling modifies
  }
}

output "db_endpoint" { value = aws_rds_cluster.main.endpoint }
