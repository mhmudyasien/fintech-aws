#!/bin/bash
# 03-ecs.sh
# Production-ready ECS setup
# Idempotent: Checks for existing resources before creating.

set -e

PROJECT="fintech"
ENV="production"
AWS_REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Load state
if [ -f .env_state ]; then
  source .env_state
else
  echo "Error: .env_state not found. Run 02-vpc.sh first."
  exit 1
fi

get_security_group_id() {
  aws ec2 describe-security-groups --filters "Name=group-name,Values=$1" "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[0].GroupId" --output text | grep -v "None" || echo ""
}

echo "--- Starting ECS Setup ---"

# 1. ECR
REPO_NAME="${PROJECT}-api"
REPO_URI=$(aws ecr describe-repositories --repository-names $REPO_NAME --query "repositories[0].repositoryUri" --output text 2>/dev/null || echo "")

if [ -z "$REPO_URI" ]; then
    echo "Creating ECR Repository..."
    REPO_URI=$(aws ecr create-repository \
      --repository-name $REPO_NAME \
      --image-scanning-configuration scanOnPush=true \
      --encryption-configuration encryptionType=AES256 \
      --tags "Key=Project,Value=$PROJECT" "Key=Environment,Value=$ENV" \
      --query 'repository.repositoryUri' --output text)
else
    echo "ECR Repo exists: $REPO_URI"
fi

# 2. Cluster
CLUSTER_NAME="${PROJECT}-cluster"
CLUSTER_ARN=$(aws ecs describe-clusters --clusters $CLUSTER_NAME --query "clusters[0].clusterArn" --output text | grep -v "MISSING" || echo "")

if [ -z "$CLUSTER_ARN" ]; then
    echo "Creating ECS Cluster..."
    CLUSTER_ARN=$(aws ecs create-cluster \
      --cluster-name $CLUSTER_NAME \
      --capacity-providers FARGATE FARGATE_SPOT \
      --default-capacity-provider-strategy capacityProvider=FARGATE_SPOT,weight=2 capacityProvider=FARGATE,weight=1 \
      --tags "Key=Project,Value=$PROJECT" "Key=Environment,Value=$ENV" \
      --query 'cluster.clusterArn' --output text)
else
    echo "ECS Cluster exists: $CLUSTER_NAME"
fi

# 3. Security Groups
# ALB SG
ALB_SG_NAME="${PROJECT}-alb-sg"
ALB_SG_ID=$(get_security_group_id $ALB_SG_NAME)
if [ -z "$ALB_SG_ID" ]; then
    echo "Creating ALB Security Group..."
    ALB_SG_ID=$(aws ec2 create-security-group --group-name $ALB_SG_NAME --description "ALB Security Group" --vpc-id $VPC_ID --query 'GroupId' --output text)
    aws ec2 authorize-security-group-ingress --group-id $ALB_SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
    aws ec2 authorize-security-group-ingress --group-id $ALB_SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0
else
    echo "ALB SG exists: $ALB_SG_ID"
fi

# ECS SG
ECS_SG_NAME="${PROJECT}-ecs-sg"
ECS_SG_ID=$(get_security_group_id $ECS_SG_NAME)
if [ -z "$ECS_SG_ID" ]; then
    echo "Creating ECS Security Group..."
    ECS_SG_ID=$(aws ec2 create-security-group --group-name $ECS_SG_NAME --description "ECS Tasks Security Group" --vpc-id $VPC_ID --query 'GroupId' --output text)
    aws ec2 authorize-security-group-ingress --group-id $ECS_SG_ID --protocol tcp --port 8080 --source-group $ALB_SG_ID
else
    echo "ECS SG exists: $ECS_SG_ID"
fi

# 4. Load Balancer
ALB_NAME="${PROJECT}-alb"
ALB_ARN=$(aws elbv2 describe-load-balancers --names $ALB_NAME --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null || echo "")

if [ -z "$ALB_ARN" ]; then
    echo "Creating Application Load Balancer..."
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name $ALB_NAME \
        --subnets $PUBLIC_SUBNET_A $PUBLIC_SUBNET_B \
        --security-groups $ALB_SG_ID \
        --scheme internet-facing \
        --type application \
        --tags "Key=Project,Value=$PROJECT" "Key=Environment,Value=$ENV" \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
else
    echo "ALB exists: $ALB_ARN"
fi

# 5. Target Group
TG_NAME="${PROJECT}-api-tg"
TG_ARN=$(aws elbv2 describe-target-groups --names $TG_NAME --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null || echo "")

if [ -z "$TG_ARN" ]; then
    echo "Creating Target Group..."
    TG_ARN=$(aws elbv2 create-target-group \
        --name $TG_NAME \
        --protocol HTTP \
        --port 8080 \
        --vpc-id $VPC_ID \
        --target-type ip \
        --health-check-path /health \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
else
    echo "Target Group exists: $TG_ARN"
fi

# 6. Listener
LISTENER_ARN=$(aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --query "Listeners[?Port==\`80\`].ListenerArn" --output text | grep -v "None" || echo "")

if [ -z "$LISTENER_ARN" ]; then
    echo "Creating Listener (HTTP)..."
    aws elbv2 create-listener \
        --load-balancer-arn $ALB_ARN \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn=$TG_ARN
else
    echo "Listener exists."
fi

# Save State
echo "Updating state..."
cat >> .env_state <<EOF
export ECR_REPO_URI=$REPO_URI
export CLUSTER_ARN=$CLUSTER_ARN
export ECS_SG_ID=$ECS_SG_ID
export ALB_ARN=$ALB_ARN
export TARGET_GROUP_ARN=$TG_ARN
EOF

echo "--- ECS Setup Complete ---"
