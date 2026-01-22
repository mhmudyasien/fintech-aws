#!/bin/bash
# 99-cleanup.sh
# Destroys resources created by the scripts.

echo "WARNING: This will delete ALL resources created by the project. Press Ctrl+C to cancel or Enter to continue."
read -r

if [ -f .env_state ]; then
  source .env_state
else
  echo "Error: .env_state not found. Trying to proceed with best effort..."
fi

echo "Deleting CloudWatch Dashboard..."
aws cloudwatch delete-dashboards --dashboard-names FinTech-Operations

echo "Deleting ECS Service..."
aws ecs update-service --cluster fintech-cluster --service fintech-api-service --desired-count 0
aws ecs delete-service --cluster fintech-cluster --service fintech-api-service --force

echo "Deleting ElastiCache..."
aws elasticache delete-replication-group --replication-group-id fintech-redis-cluster --retain-primary-cluster=false
aws elasticache delete-cache-subnet-group --cache-subnet-group-name fintech-redis-subnets

echo "Deleting Aurora Cluster (Skip snapshot for demo)..."
aws rds delete-db-instance --db-instance-identifier fintech-reader --skip-final-snapshot
aws rds delete-db-instance --db-instance-identifier fintech-writer --skip-final-snapshot
echo "Waiting for DB Instances to delete..."
aws rds wait db-instance-deleted --db-instance-identifier fintech-writer

aws rds delete-db-cluster --db-cluster-identifier fintech-cluster --skip-final-snapshot
aws rds delete-db-subnet-group --db-subnet-group-name fintech-db-subnets

echo "Deleting DynamoDB..."
aws dynamodb delete-table --table-name fintech-sessions

echo "Deleting S3 Bucket..."
# Dangerous: Force delete everything
if [ -n "$BUCKET_NAME" ]; then
    aws s3 rb s3://$BUCKET_NAME --force
fi

echo "Deleting Load Balancer..."
if [ -n "$ALB_ARN" ]; then
    aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN
fi
if [ -n "$TARGET_GROUP_ARN" ]; then
    aws elbv2 delete-target-group --target-group-arn $TARGET_GROUP_ARN
fi

echo "Deleting ECR..."
aws ecr delete-repository --repository-name fintech-api --force

echo "Deleting VPC Endpoints..."
# This is tricky without IDs. In production, we'd track them.
# For now, this is a placeholder. User would need IDs.

echo "Deleting NAT Gateway..."
# Requires ID.

echo "Deleting VPC..."
# Requires tearing down subnets, routes, IGW, etc.
# Creating a full teardown script for VPC is complex due to dependencies.
if [ -n "$VPC_ID" ]; then
    echo "Please manually delete VPC $VPC_ID and its dependencies (Subnets, IGW, NAT, Endpoints) via Console or specific commands."
    echo "Automated VPC teardown is risky and requires recursive dependency deletion."
fi

echo "Cleanup initiated."
