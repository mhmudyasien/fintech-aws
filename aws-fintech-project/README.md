# AWS Fintech Project Implementation

This project implements a secure, scalable, and compliant infrastructure for a Fintech application using AWS CLI.

## Project Structure

```
aws-fintech-project/
├── scripts/
│   ├── 01-organization.sh     # AWS Organizations & Policies
│   ├── 02-vpc.sh              # Network Infrastructure (VPC, Subnets)
│   ├── 03-ecs.sh              # Compute Layer (ECS Fargate, ALB)
│   ├── 04-data-layer.sh       # Data Layer (Aurora, DynamoDB, Redis, S3)
│   ├── 05-monitoring.sh       # Observability (CloudWatch)
│   └── 99-cleanup.sh          # Resource Teardown
├── architecture/
│   └── diagram.mermaid        # Architecture Diagram
└── README.md                  # This file
```

## Prerequisites

- **AWS CLI**: Installed and configured with Administrator privileges.
- **jq**: Command-line JSON processor (recommended for parsing outputs).
- **Bash**: Scripts are written in Bash. Windows users should use Git Bash or WSL.

## Implementation Steps

Run the scripts in the following order. The scripts use a `.env_state` file to pass resource IDs (like `VPC_ID`) between steps.

### 1. Organization Setup
Set up the AWS Organization structure and Service Control Policies (SCPs).
```bash
./scripts/01-organization.sh
```
*Note: SCP creation might fail if you are not in the Management Account of an Organization.*

### 2. Network Infrastructure
Create the VPC, Public/Private subnets, NAT Gateways, and VPC Endpoints.
```bash
./scripts/02-vpc.sh
```

### 3. Compute Layer
Set up the ECS Fargate Cluster, Load Balancer, and Security Groups.
```bash
./scripts/03-ecs.sh
```
*Note: This script registers the Task Definition concepts but relies on Secrets created in Step 4. If strict ordering is required by AWS validation, run Step 4 before the final Task Definition registration in Step 3.*

### 4. Data Layer & Secrets
Provision Aurora PostgreSQL, DynamoDB, ElastiCache Redis, S3 Data Lake, and Secrets Manager secrets.
```bash
./scripts/04-data-layer.sh
```

### 5. Monitoring & Observability
Create CloudWatch Dashboards and Alarms.
```bash
./scripts/05-monitoring.sh
```

## Architecture

See `architecture/diagram.mermaid` for a visual representation.

**Key Components:**
- **VPC**: 3-tier architecture (Public, Private App, Private Data).
- **Compute**: ECS Fargate with Auto Scaling.
- **Data**: Aurora PostgreSQL (Relational), DynamoDB (NoSQL), Redis (Caching), S3 (Data Lake).
- **Security**: Private Subnets, Security Groups, KMS Encryption, Secrets Manager.

## Cleanup

To remove the created resources:
```bash
./scripts/99-cleanup.sh
```
*Warning: This script attempts to delete resources but might require manual intervention for dependencies like VPCs with active network interfaces.*
