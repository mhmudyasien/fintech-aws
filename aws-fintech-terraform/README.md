# AWS Fintech Project - Terraform Implementation

## Overview
This directory contains the Terraform Infrastructure as Code (IaC) to deploy the Fintech project. It replaces the previous Bash scripts with a declarative, state-managed approach.

## Structure

- **main.tf**: Entry point, calls all modules.
- **variables.tf**: Configuration (Region, CIDR).
- **modules/**
  - **networking**: VPC, Subnets, NAT, VPC Endpoints.
  - **compute**: ECS Fargate, ALB, ECR.
  - **database**: Aurora PostgreSQL, Redis, DynamoDB.
  - **storage**: S3 Data Lake.

## Prerequisites

1.  **Terraform**: [Install Terraform](https://developer.hashicorp.com/terraform/downloads) (v1.0+).
2.  **AWS CLI**: Configured with credentials (`aws configure`).
3.  **Cleanup**: Ensure resources from previous bash scripts are DELETED to avoid conflicts.

## Deployment Steps

1.  **Initialize**: Download providers and modules.
    ```bash
    terraform init
    ```

2.  **Plan**: Preview changes.
    ```bash
    terraform plan
    ```

3.  **Apply**: Create infrastructure.
    ```bash
    terraform apply
    # Type 'yes' to confirm
    ```

4.  **Destroy**: Teardown everything.
    ```bash
    terraform destroy
    ```

## Outputs
After a successful apply, Terraform will output:
- `alb_url`: Load Balancer DNS (Access your API here).
- `ecr_repo`: Registry URL to push your Docker images.
- `db_endpoint`: Database connection string.
- `s3_bucket`: Logic bucket name.
