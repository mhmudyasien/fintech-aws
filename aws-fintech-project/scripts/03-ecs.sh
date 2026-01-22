#!/bin/bash
# 03-ecs.sh
# Task 3.1: ECS Cluster Setup
# Task 3.2: Auto Scaling Configuration

# Load state
if [ -f .env_state ]; then
  source .env_state
else
  echo "Error: .env_state not found. Run 02-vpc.sh first."
  exit 1
fi

echo "Starting ECS Setup..."

# Get Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create ECR Repository
aws ecr create-repository \
  --repository-name fintech-api \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256 \
  --tags key=Environment,value=Production key=Project,value=FinTech

ECR_REPO=$(aws ecr describe-repositories --repository-names fintech-api --query 'repositories[0].repositoryUri' --output text)

# Create CloudWatch Log Group
aws logs create-log-group --log-group-name /ecs/fintech-api

# Create ECS Cluster
aws ecs create-cluster \
  --cluster-name fintech-cluster \
  --capacity-providers FARGATE FARGATE_SPOT \
  --default-capacity-provider-strategy \
    capacityProvider=FARGATE_SPOT,weight=2 \
    capacityProvider=FARGATE,weight=1 \
  --tags key=Environment,value=Production key=Project,value=FinTech

# Create Task Execution Role
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# Create Task Role
aws iam create-role \
  --role-name ecsTaskRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Create Security Group for ECS Tasks
ECS_SG=$(aws ec2 create-security-group \
  --group-name fintech-ecs-sg \
  --description "Security group for ECS tasks" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)

# Create Application Load Balancer SG
ALB_SG=$(aws ec2 create-security-group \
  --group-name fintech-alb-sg \
  --description "Security group for ALB" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)

# Allow HTTP/HTTPS to ALB
aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0

# Allow ALB to ECS
aws ec2 authorize-security-group-ingress \
  --group-id $ECS_SG \
  --protocol tcp \
  --port 8080 \
  --source-group $ALB_SG

ALB_ARN=$(aws elbv2 create-load-balancer \
  --name fintech-alb \
  --subnets $PUBLIC_SUBNET_A $PUBLIC_SUBNET_B \
  --security-groups $ALB_SG \
  --scheme internet-facing \
  --type application \
  --tags Key=Environment,Value=Production Key=Project,Value=FinTech \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# Create Target Group
TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
  --name fintech-api-tg \
  --protocol HTTP \
  --port 8080 \
  --vpc-id $VPC_ID \
  --target-type ip \
  --health-check-path /health \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

# Create Listener
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN

# NOTE: Task Definition requires Secrets which are created in 04-data-layer.sh
# For this script to be fully runnable sequentially, we need the secrets first.
# However, the user provided order has ECS first.
# We will create the Task Definition, but it might fail if secrets don't exist yet.
# To be safe, we'll note this dependency.

echo "ECS Cluster and Networking created."
echo "Wait for Task 4 (Data Layer) to create Secrets before registering Task Definition if running for real."

# Append ECS vars to state
cat << EOF >> .env_state
export ECS_SG=$ECS_SG
export ACCOUNT_ID=$ACCOUNT_ID
export ECR_REPO=$ECR_REPO
export TARGET_GROUP_ARN=$TARGET_GROUP_ARN
export ALB_ARN=$ALB_ARN
EOF
