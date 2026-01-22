# Service Integration & Command Reference

## 1. AWS Organizations & Tagging
**Goal**: Enforce centralized governance and security.
- **Service Control Policies (SCPs)**: JSON documents that restrict what actions can be taken in member accounts.
  - `DenyRootUserAccess`: Prevents the use of the root user for enhanced security.
  - `RegionRestriction`: Ensures resources are only deployed in `us-east-1`.
- **Tag Policies**: Enforce standard tagging (e.g., `Environment`, `CostCenter`) across resources for cost tracking and management.

## 2. Networking (VPC)
**Goal**: Isolate resources in a secure network.
- **VPC** (`aws ec2 create-vpc`): The isolated network container.
- **Subnets**:
  - **Public**: Host the NAT Gateway and Load Balancer. Accessible from the internet.
  - **Private App**: Host ECS Tasks. Can reach internet only via NAT Gateway.
  - **Private Data**: Host Databases. No internet access.
- **NAT Gateway** (`aws ec2 create-nat-gateway`): Allows private instances to initiate outbound traffic (e.g., download updates) without accepting inbound traffic.
- **VPC Endpoints** (`aws ec2 create-vpc-endpoint`): Allow private access to AWS services (S3, ECR, Secrets Manager) without traversing the public internet, improving security and reducing latency.

## 3. Compute (ECS Fargate)
**Goal**: Run containerized applications without managing servers.
- **Cluster** (`aws ecs create-cluster`): Logical grouping of tasks.
- **Task Definition**: Blueprints for your application. We inject secrets from Secrets Manager directly as environment variables.
- **Service** (`aws ecs create-service`): Maintains the desired number of tasks (3) and handles replacement if they fail.
- **Auto Scaling**:
  - `aws application-autoscaling`: Dynamically adjusts the number of tasks based on CPU utilization (Target Tracking).

## 4. Data Layer
**Goal**: diverse storage options for different data needs.
- **Aurora PostgreSQL**: Primary relational database.
  - **Storage Encrypted**: Uses KMS keys for data at rest.
  - **Multi-AZ**: Writer and Reader instances in different zones for high availability.
- **DynamoDB**: High-speed NoSQL for session data.
  - **Provisioined Throughput**: explicit capacity units.
  - **Auto Scaling**: Automatically adjusts capacity units based on load.
- **ElastiCache Redis**: In-memory caching to reduce database load.
  - `create-replication-group`: Creates a cluster with automatic failover.
- **S3**: Data Lake for raw and processed data.
  - **Lifecycle Policies**: Move old data to cheaper storage (Glacier) automatically.

## 5. Security & Secrets
**Goal**: Protect sensitive data.
- **KMS** (`aws kms create-key`): Manages encryption keys used by RDS, S3, and Secrets Manager.
- **Secrets Manager**: Stores database credentials and API keys.
  - **Integration**: ECS fetches these secrets at runtime, so they are never hardcoded in scripts or Docker images.
