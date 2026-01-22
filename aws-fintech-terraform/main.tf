module "networking" {
  source       = "./modules/networking"
  project_name = var.project_name
  environment  = var.environment
  region       = var.region
  vpc_cidr     = var.vpc_cidr
}

# KMS Key removed to save cost ($1/mo)
# Using AWS Managed Keys (AES256) instead.

module "storage" {
  source       = "./modules/storage"
  project_name = var.project_name
  environment  = var.environment
}

module "compute" {
  source              = "./modules/compute"
  project_name        = var.project_name
  environment         = var.environment
  region              = var.region
  vpc_id              = module.networking.vpc_id
  public_subnets      = module.networking.public_subnets
}

module "database" {
  source               = "./modules/database"
  project_name         = var.project_name
  environment          = var.environment
  vpc_id               = module.networking.vpc_id
  private_data_subnets = module.networking.private_data_subnets
  app_sg_id            = module.compute.ecs_sg_id
}

output "vpc_id" { value = module.networking.vpc_id }
output "alb_url" { value = module.compute.alb_dns_name }
output "ecr_repo" { value = module.compute.ecr_url }
output "db_endpoint" { value = module.database.db_endpoint }
output "s3_bucket" { value = module.storage.bucket_name }
