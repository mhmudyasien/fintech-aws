module "networking" {
  source       = "./modules/networking"
  project_name = var.project_name
  environment  = var.environment
  region       = var.region
  vpc_cidr     = var.vpc_cidr
}

resource "aws_kms_key" "main" {
  description             = "Master Key for Fintech Project"
  deletion_window_in_days = 7
}

module "storage" {
  source       = "./modules/storage"
  project_name = var.project_name
  environment  = var.environment
  kms_key_arn  = aws_kms_key.main.arn
}

module "compute" {
  source              = "./modules/compute"
  project_name        = var.project_name
  environment         = var.environment
  region              = var.region
  vpc_id              = module.networking.vpc_id
  public_subnets      = module.networking.public_subnets
  private_app_subnets = module.networking.private_app_subnets
}

module "database" {
  source               = "./modules/database"
  project_name         = var.project_name
  environment          = var.environment
  vpc_id               = module.networking.vpc_id
  private_data_subnets = module.networking.private_data_subnets
  app_sg_id            = module.compute.ecs_sg_id
  kms_key_id           = aws_kms_key.main.arn
}

output "vpc_id" { value = module.networking.vpc_id }
output "alb_url" { value = module.compute.alb_dns_name }
output "ecr_repo" { value = module.compute.ecr_url }
output "db_endpoint" { value = module.database.db_endpoint }
output "s3_bucket" { value = module.storage.bucket_name }
