#!/bin/bash
# 04-data-layer.sh
# Task 4.1: Aurora PostgreSQL Cluster
# Task 4.2: DynamoDB Tables
# Task 4.3: S3 Data Lake
# Task 4.4: ElastiCache Redis
# Task 4.5: Secrets Manager

# Load state
if [ -f .env_state ]; then
  source .env_state
else
  echo "Error: .env_state not found. Run 02-vpc.sh and 03-ecs.sh first."
  exit 1
fi

echo "Starting Data Layer Setup..."

# Create KMS Key
KMS_KEY_ID=$(aws kms create-key \
  --description "FinTech RDS encryption key" \
  --tags TagKey=Project,TagValue=FinTech TagKey=Environment,TagValue=Production \
  --query 'KeyMetadata.KeyId' --output text)

echo "KMS Key Created: $KMS_KEY_ID"

# --- AURORA POSTGRESQL ---

# Create DB Subnet Group
aws rds create-db-subnet-group \
  --db-subnet-group-name fintech-db-subnets \
  --db-subnet-group-description "Subnets for FinTech Aurora cluster" \
  --subnet-ids $DB_SUBNET_A $DB_SUBNET_B

# Create Security Group for Aurora
DB_SG=$(aws ec2 create-security-group \
  --group-name fintech-db-sg \
  --description "Security group for Aurora database" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)

# Allow ECS to DB
aws ec2 authorize-security-group-ingress \
  --group-id $DB_SG \
  --protocol tcp \
  --port 5432 \
  --source-group $ECS_SG

# Generate and Store Database Credentials
DB_PASSWORD=$(openssl rand -base64 32)
aws secretsmanager create-secret \
  --name fintech/db-credentials \
  --description "FinTech Aurora database credentials" \
  --secret-string "{\"username\":\"fintechadmin\",\"password\":\"$DB_PASSWORD\",\"engine\":\"postgres\",\"port\":5432,\"dbname\":\"fintech\"}" \
  --kms-key-id $KMS_KEY_ID

# Create Aurora Cluster
aws rds create-db-cluster \
  --db-cluster-identifier fintech-cluster \
  --engine aurora-postgresql \
  --engine-version 15.4 \
  --master-username fintechadmin \
  --master-user-password $DB_PASSWORD \
  --db-subnet-group-name fintech-db-subnets \
  --vpc-security-group-ids $DB_SG \
  --storage-encrypted \
  --kms-key-id $KMS_KEY_ID \
  --backup-retention-period 35 \
  --preferred-backup-window "03:00-04:00" \
  --enable-cloudwatch-logs-exports postgresql \
  --deletion-protection \
  --enable-http-endpoint \
  --database-name fintech

# Create Monitor Role
MONITORING_ROLE_ARN=$(aws iam create-role \
  --role-name rds-monitoring-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "monitoring.rds.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }' \
  --query 'Role.Arn' --output text)

aws iam attach-role-policy \
  --role-name rds-monitoring-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole

# Create Instances
aws rds create-db-instance \
  --db-instance-identifier fintech-writer \
  --db-instance-class db.r6g.large \
  --db-cluster-identifier fintech-cluster \
  --engine aurora-postgresql \
  --enable-performance-insights \
  --performance-insights-retention-period 7 \
  --monitoring-interval 60 \
  --monitoring-role-arn $MONITORING_ROLE_ARN \
  --publicly-accessible false

aws rds create-db-instance \
  --db-instance-identifier fintech-reader \
  --db-instance-class db.r6g.large \
  --db-cluster-identifier fintech-cluster \
  --engine aurora-postgresql \
  --enable-performance-insights \
  --publicly-accessible false

# --- DYNAMODB ---

aws dynamodb create-table \
  --table-name fintech-sessions \
  --attribute-definitions \
    AttributeName=userId,AttributeType=S \
    AttributeName=sessionId,AttributeType=S \
  --key-schema \
    AttributeName=userId,KeyType=HASH \
    AttributeName=sessionId,KeyType=RANGE \
  --billing-mode PROVISIONED \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
  --sse-specification Enabled=true,SSEType=KMS,KMSMasterKeyId=$KMS_KEY_ID \
  --tags Key=Project,Value=FinTech Key=Environment,Value=Production

# DynamoDB Auto Scaling (Policies omitted for brevity, see needs.md)

# --- S3 DATA LAKE ---

BUCKET_NAME="fintech-data-lake-$(date +%s)"
aws s3api create-bucket --bucket $BUCKET_NAME --region us-east-1

aws s3api put-bucket-versioning --bucket $BUCKET_NAME --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms",
        "KMSMasterKeyID": "'$KMS_KEY_ID'"
      },
      "BucketKeyEnabled": true
    }]
  }'

aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# S3 Structure
aws s3api put-object --bucket $BUCKET_NAME --key raw/transactions/
aws s3api put-object --bucket $BUCKET_NAME --key raw/logs/
aws s3api put-object --bucket $BUCKET_NAME --key processed/daily-reports/


# --- ELASTICACHE REDIS ---

aws elasticache create-cache-subnet-group \
  --cache-subnet-group-name fintech-redis-subnets \
  --cache-subnet-group-description "Subnets for FinTech Redis cluster" \
  --subnet-ids $DB_SUBNET_A $DB_SUBNET_B

REDIS_SG=$(aws ec2 create-security-group \
  --group-name fintech-redis-sg \
  --description "Security group for ElastiCache Redis" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress \
  --group-id $REDIS_SG \
  --protocol tcp \
  --port 6379 \
  --source-group $ECS_SG

REDIS_AUTH_TOKEN=$(openssl rand -base64 32)

aws secretsmanager create-secret \
  --name fintech/redis-auth \
  --description "ElastiCache Redis authentication token" \
  --secret-string $REDIS_AUTH_TOKEN \
  --kms-key-id $KMS_KEY_ID

aws elasticache create-replication-group \
  --replication-group-id fintech-redis-cluster \
  --description "FinTech Redis cluster for caching" \
  --engine redis \
  --engine-version 7.0 \
  --node-type cache.r6g.large \
  --num-cache-clusters 2 \
  --cache-subnet-group-name fintech-redis-subnets \
  --security-group-ids $REDIS_SG \
  --at-rest-encryption-enabled \
  --transit-encryption-enabled \
  --auth-token "$REDIS_AUTH_TOKEN" \
  --automatic-failover-enabled \
  --multi-az-enabled \
  --snapshot-retention-limit 7 \
  --tags Key=Project,Value=FinTech Key=Environment,Value=Production

# --- ADDITIONAL SECRETS ---

aws secretsmanager create-secret \
  --name fintech/api-keys \
  --description "API keys for external services" \
  --secret-string '{
    "stripe_api_key": "sk_live_xxxxx",
    "sendgrid_api_key": "SG.xxxxx"
  }' \
  --kms-key-id $KMS_KEY_ID

# Grant Access to ECS Role
aws iam put-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-name SecretsManagerAccess \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
        "arn:aws:secretsmanager:us-east-1:'$ACCOUNT_ID':secret:fintech/*"
      ]
    }]
  }'

# --- ECS SERVICE CREATION (Delayed from 03-ecs.sh) ---

# Register Task Definition
aws ecs register-task-definition \
  --family fintech-api \
  --network-mode awsvpc \
  --requires-compatibilities FARGATE \
  --cpu 512 \
  --memory 1024 \
  --execution-role-arn arn:aws:iam::$ACCOUNT_ID:role/ecsTaskExecutionRole \
  --task-role-arn arn:aws:iam::$ACCOUNT_ID:role/ecsTaskRole \
  --container-definitions "[
    {
      \"name\": \"api-container\",
      \"image\": \"$ECR_REPO:latest\",
      \"portMappings\": [{\"containerPort\": 8080, \"protocol\": \"tcp\"}],
      \"secrets\": [
        {\"name\": \"DB_PASSWORD\", \"valueFrom\": \"arn:aws:secretsmanager:us-east-1:$ACCOUNT_ID:secret:fintech/db-credentials:password::\"},
        {\"name\": \"API_KEY\", \"valueFrom\": \"arn:aws:secretsmanager:us-east-1:$ACCOUNT_ID:secret:fintech/api-keys\"}
      ],
      \"environment\": [
        {\"name\": \"ENVIRONMENT\", \"value\": \"production\"},
        {\"name\": \"REGION\", \"value\": \"us-east-1\"}
      ],
      \"logConfiguration\": {
        \"logDriver\": \"awslogs\",
        \"options\": {
          \"awslogs-group\": \"/ecs/fintech-api\",
          \"awslogs-region\": \"us-east-1\",
          \"awslogs-stream-prefix\": \"ecs\"
        }
      }
    }
  ]"

# Create ECS Service
aws ecs create-service \
  --cluster fintech-cluster \
  --service-name fintech-api-service \
  --task-definition fintech-api \
  --desired-count 3 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNET_A,$PRIVATE_SUBNET_B],securityGroups=[$ECS_SG],assignPublicIp=DISABLED}" \
  --load-balancers targetGroupArn=$TARGET_GROUP_ARN,containerName=api-container,containerPort=8080 \
  --health-check-grace-period-seconds 60


cat << EOF >> .env_state
export KMS_KEY_ID=$KMS_KEY_ID
export BUCKET_NAME=$BUCKET_NAME
EOF

echo "Data Layer Setup Complete."
