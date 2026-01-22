# AWS Fintech Project - Terraform Implementation (Free Tier)

## Overview
This configuration is optimized for the **AWS Free Tier**. It deploys a functional Fintech infrastructure while minimizing costs by using eligible instance types and removing optional paid features.

## Free Tier Optimizations
- **Compute**: Uses EC2 `t2.micro` (750h free) instead of Fargate.
- **Database**: Uses RDS `db.t3.micro` and Redis `cache.t2.micro`.
- **Networking**: NAT Gateways removed (ECS runs in Public Subnets).
- **Storage**: Standard S3 with managed encryption (no custom KMS cost).

## Structure
- **main.tf**: Entry point.
- **modules/**:
  - **networking**: VPC, Public (App) & Private (Data) Subnets.
  - **compute**: ECS Cluster with Auto Scaling Group (EC2 Launch Type).
  - **database**: RDS PostgreSQL & Redis (Single Node).
  - **storage**: S3 Data Lake.

## Deployment Steps

1.  **Cleanup Old State** (Critical if retrying):
    ```bash
    rm terraform.tfstate*
    rm -rf .terraform/
    ```

2.  **Initialize**:
    ```bash
    terraform init
    ```

3.  **Apply**:
    ```bash
    terraform apply
    ```

## Outputs
- `alb_url`: API Endpoint.
- `ecr_repo`: Docker Registry.
- `db_endpoint`: Database Host.
