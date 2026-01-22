
Task 1.1: AWS Organizations Setup (30 Points)

Root Account (Management)
├── Security OU
│   ├── Security-Audit Account
│   └── Security-Logging Account
├── Infrastructure OU
│   ├── Shared-Services Account
│   └── Network-Hub Account
├── Workloads OU
│   ├── Production OU
│   │   ├── Prod-US Account
│   │   └── Prod-EU Account
│   ├── Staging OU
│   │   └── Staging Account
│   └── Development OU
│       └── Dev Account
└── Sandbox OU
    └── Sandbox Account
---
# Create Organization
aws organizations create-organization --feature-set ALL

# Create OUs
aws organizations create-organizational-unit \
  --parent-id r-xxxx \
  --name "Security"

aws organizations create-organizational-unit \
  --parent-id r-xxxx \
  --name "Workloads"

# Create SCP - Deny Root User
cat > deny-root-scp.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyRootUser",
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:PrincipalArn": "arn:aws:iam::*:root"
        }
      }
    }
  ]
}
EOF

aws organizations create-policy \
  --name "DenyRootUserAccess" \
  --description "Deny all actions for root user" \
  --type SERVICE_CONTROL_POLICY \
  --content file://deny-root-scp.json

# Create SCP - Region Restriction
cat > region-restriction-scp.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyNonApprovedRegions",
      "Effect": "Deny",
      "NotAction": [
        "iam:*",
        "organizations:*",
        "support:*",
        "sts:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:RequestedRegion": ["us-east-1"]
        }
      }
    }
  ]
}
EOF

---


Task 1.2: Tagging Strategy (20 Points)

# Create Tag Policy
cat > tag-policy.json << 'EOF'
{
  "tags": {
    "Environment": {
      "tag_key": {"@@assign": "Environment"},
      "tag_value": {
        "@@assign": ["Production", "Staging", "Development", "Sandbox"]
      },
      "enforced_for": {
        "@@assign": [
          "ec2:instance",
          "ec2:volume",
          "rds:db",
          "s3:bucket",
          "dynamodb:table"
        ]
      }
    },
    "Project": {
      "tag_key": {"@@assign": "Project"}
    },
    "CostCenter": {
      "tag_key": {"@@assign": "CostCenter"},
      "tag_value": {"@@assign": ["CC-*"]}
    },
    "Owner": {
      "tag_key": {"@@assign": "Owner"}
    },
    "DataClassification": {
      "tag_key": {"@@assign": "DataClassification"},
      "tag_value": {"@@assign": ["Confidential", "Internal", "Public"]}
    }
  }
}
EOF

aws organizations create-policy \
  --name "FinTechTagPolicy" \
  --type TAG_POLICY \
  --content file://tag-policy.json

# Create Config Rule for Tag Compliance
aws configservice put-config-rule \
  --config-rule '{
    "ConfigRuleName": "required-tags",
    "Source": {
      "Owner": "AWS",
      "SourceIdentifier": "REQUIRED_TAGS"
    },
    "InputParameters": "{\"tag1Key\":\"Environment\",\"tag2Key\":\"Project\",\"tag3Key\":\"CostCenter\",\"tag4Key\":\"Owner\"}"
  }'

---

Task 1.3: Well-Architected Workload (25 Points)

# Create Tag Policy
cat > tag-policy.json << 'EOF'
{
  "tags": {
    "Environment": {
      "tag_key": {"@@assign": "Environment"},
      "tag_value": {
        "@@assign": ["Production", "Staging", "Development", "Sandbox"]
      },
      "enforced_for": {
        "@@assign": [
          "ec2:instance",
          "ec2:volume",
          "rds:db",
          "s3:bucket",
          "dynamodb:table"
        ]
      }
    },
    "Project": {
      "tag_key": {"@@assign": "Project"}
    },
    "CostCenter": {
      "tag_key": {"@@assign": "CostCenter"},
      "tag_value": {"@@assign": ["CC-*"]}
    },
    "Owner": {
      "tag_key": {"@@assign": "Owner"}
    },
    "DataClassification": {
      "tag_key": {"@@assign": "DataClassification"},
      "tag_value": {"@@assign": ["Confidential", "Internal", "Public"]}
    }
  }
}
EOF

aws organizations create-policy \
  --name "FinTechTagPolicy" \
  --type TAG_POLICY \
  --content file://tag-policy.json

# Create Config Rule for Tag Compliance
aws configservice put-config-rule \
  --config-rule '{
    "ConfigRuleName": "required-tags",
    "Source": {
      "Owner": "AWS",
      "SourceIdentifier": "REQUIRED_TAGS"
    },
    "InputParameters": "{\"tag1Key\":\"Environment\",\"tag2Key\":\"Project\",\"tag3Key\":\"CostCenter\",\"tag4Key\":\"Owner\"}"
  }'

----

Task 2.1: VPC Architecture (40 Points)


# Create Production VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=fintech-prod-vpc},{Key=Environment,Value=Production}]' \
  --query 'Vpc.VpcId' --output text)

# Enable DNS
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames '{"Value":true}'
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support '{"Value":true}'

# Get Availability Zones
AZ_A=$(aws ec2 describe-availability-zones --region us-east-1 --query 'AvailabilityZones[0].ZoneName' --output text)
AZ_B=$(aws ec2 describe-availability-zones --region us-east-1 --query 'AvailabilityZones[1].ZoneName' --output text)

# Create Public Subnets
PUBLIC_SUBNET_A=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone $AZ_A \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=fintech-public-az-a}]' \
  --query 'Subnet.SubnetId' --output text)

PUBLIC_SUBNET_B=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone $AZ_B \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=fintech-public-az-b}]' \
  --query 'Subnet.SubnetId' --output text)

# Create Private App Subnets
PRIVATE_SUBNET_A=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.11.0/24 \
  --availability-zone $AZ_A \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=fintech-private-app-az-a}]' \
  --query 'Subnet.SubnetId' --output text)

PRIVATE_SUBNET_B=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.12.0/24 \
  --availability-zone $AZ_B \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=fintech-private-app-az-b}]' \
  --query 'Subnet.SubnetId' --output text)

# Create Database Subnets
DB_SUBNET_A=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.21.0/24 \
  --availability-zone $AZ_A \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=fintech-db-az-a}]' \
  --query 'Subnet.SubnetId' --output text)

DB_SUBNET_B=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.22.0/24 \
  --availability-zone $AZ_B \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=fintech-db-az-b}]' \
  --query 'Subnet.SubnetId' --output text)

# Create Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=fintech-igw}]' \
  --query 'InternetGateway.InternetGatewayId' --output text)

aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID

# Create Route Table for Public Subnets
PUBLIC_RT_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=fintech-public-rt}]' \
  --query 'RouteTable.RouteTableId' --output text)

aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_A --route-table-id $PUBLIC_RT_ID
aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_B --route-table-id $PUBLIC_RT_ID

# Create Route Table for Private Subnets
PRIVATE_RT_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=fintech-private-rt}]' \
  --query 'RouteTable.RouteTableId' --output text)

# Create NAT Gateway
EIP_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
NAT_GW_ID=$(aws ec2 create-nat-gateway \
  --subnet-id $PUBLIC_SUBNET_A \
  --allocation-id $EIP_ID \
  --tag-specifications 'ResourceType=nat-gateway,Tags=[{Key=Name,Value=fintech-nat-gw}]' \
  --query 'NatGateway.NatGatewayId' --output text)

# Wait for NAT Gateway to be available
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW_ID

# Add route to NAT Gateway
aws ec2 create-route --route-table-id $PRIVATE_RT_ID --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW_ID
aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_A --route-table-id $PRIVATE_RT_ID
aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_B --route-table-id $PRIVATE_RT_ID

# Create VPC Endpoints
aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.us-east-1.s3 \
  --vpc-endpoint-type Gateway \
  --route-table-ids $PRIVATE_RT_ID

# Create Security Group for VPC Endpoints
VPC_ENDPOINT_SG=$(aws ec2 create-security-group \
  --group-name fintech-vpc-endpoint-sg \
  --description "Security group for VPC endpoints" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)

aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.us-east-1.ecr.api \
  --vpc-endpoint-type Interface \
  --subnet-ids $PRIVATE_SUBNET_A $PRIVATE_SUBNET_B \
  --security-group-ids $VPC_ENDPOINT_SG \
  --private-dns-enabled

aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.us-east-1.ecr.dkr \
  --vpc-endpoint-type Interface \
  --subnet-ids $PRIVATE_SUBNET_A $PRIVATE_SUBNET_B \
  --security-group-ids $VPC_ENDPOINT_SG \
  --private-dns-enabled

aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.us-east-1.secretsmanager \
  --vpc-endpoint-type Interface \
  --subnet-ids $PRIVATE_SUBNET_A $PRIVATE_SUBNET_B \
  --security-group-ids $VPC_ENDPOINT_SG \
  --private-dns-enabled

----

Task 3.1: ECS Cluster Setup (60 Points)


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

# Create Task Execution Role with Secrets Manager permissions
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

# Create Application Load Balancer
ALB_SG=$(aws ec2 create-security-group \
  --group-name fintech-alb-sg \
  --description "Security group for ALB" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)

# Allow HTTP/HTTPS from internet to ALB
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

# Allow ALB to communicate with ECS tasks
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

# Register Task Definition with Secrets Manager integration
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

# Create ECS Service with Auto Scaling
aws ecs create-service \
  --cluster fintech-cluster \
  --service-name fintech-api-service \
  --task-definition fintech-api \
  --desired-count 3 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNET_A,$PRIVATE_SUBNET_B],securityGroups=[$ECS_SG],assignPublicIp=DISABLED}" \
  --load-balancers targetGroupArn=$TARGET_GROUP_ARN,containerName=api-container,containerPort=8080 \
  --health-check-grace-period-seconds 60

# Register Auto Scaling Target
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/fintech-cluster/fintech-api-service \
  --min-capacity 3 \
  --max-capacity 10

# Create Auto Scaling Policy
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/fintech-cluster/fintech-api-service \
  --policy-name cpu-scaling-policy \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
    },
    "ScaleInCooldown": 300,
    "ScaleOutCooldown": 60
  }'


Task 3.2: Auto Scaling Configuration (50 Points)


Task 4.1: Aurora PostgreSQL Cluster (50 Points)

# Create KMS Key for RDS encryption
KMS_KEY_ID=$(aws kms create-key \
  --description "FinTech RDS encryption key" \
  --tags TagKey=Project,TagValue=FinTech TagKey=Environment,TagValue=Production \
  --query 'KeyMetadata.KeyId' --output text)

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

# Allow ECS tasks to access database
aws ec2 authorize-security-group-ingress \
  --group-id $DB_SG \
  --protocol tcp \
  --port 5432 \
  --source-group $ECS_SG

# Generate secure password
DB_PASSWORD=$(openssl rand -base64 32)

# Create Secrets Manager secret for database credentials
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

# Create IAM Role for Enhanced Monitoring
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

# Create Writer Instance
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

# Create Reader Instance (Multi-AZ)
aws rds create-db-instance \
  --db-instance-identifier fintech-reader \
  --db-instance-class db.r6g.large \
  --db-cluster-identifier fintech-cluster \
  --engine aurora-postgresql \
  --enable-performance-insights \
  --publicly-accessible false

# Wait for cluster to be available
aws rds wait db-cluster-available --db-cluster-identifier fintech-cluster

# Enable Aurora Auto Scaling
aws application-autoscaling register-scalable-target \
  --service-namespace rds \
  --resource-id cluster:fintech-cluster \
  --scalable-dimension rds:cluster:ReadReplicaCount \
  --min-capacity 1 \
  --max-capacity 5

aws application-autoscaling put-scaling-policy \
  --service-namespace rds \
  --resource-id cluster:fintech-cluster \
  --scalable-dimension rds:cluster:ReadReplicaCount \
  --policy-name aurora-replica-scaling \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "RDSReaderAverageCPUUtilization"
    },
    "ScaleInCooldown": 300,
    "ScaleOutCooldown": 60
  }'

--

Task 4.2: DynamoDB Tables (40 Points)


# Create DynamoDB Table with Auto Scaling
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

# Enable Auto Scaling for Reads
aws application-autoscaling register-scalable-target \
  --service-namespace dynamodb \
  --scalable-dimension dynamodb:table:ReadCapacityUnits \
  --resource-id table/fintech-sessions \
  --min-capacity 5 \
  --max-capacity 100

aws application-autoscaling put-scaling-policy \
  --service-namespace dynamodb \
  --scalable-dimension dynamodb:table:ReadCapacityUnits \
  --resource-id table/fintech-sessions \
  --policy-name read-scaling-policy \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "DynamoDBReadCapacityUtilization"
    },
    "ScaleInCooldown": 60,
    "ScaleOutCooldown": 60
  }'

# Enable Auto Scaling for Writes
aws application-autoscaling register-scalable-target \
  --service-namespace dynamodb \
  --scalable-dimension dynamodb:table:WriteCapacityUnits \
  --resource-id table/fintech-sessions \
  --min-capacity 5 \
  --max-capacity 100

aws application-autoscaling put-scaling-policy \
  --service-namespace dynamodb \
  --scalable-dimension dynamodb:table:WriteCapacityUnits \
  --resource-id table/fintech-sessions \
  --policy-name write-scaling-policy \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "DynamoDBWriteCapacityUtilization"
    },
    "ScaleInCooldown": 60,
    "ScaleOutCooldown": 60
  }'


---

Task 4.3: S3 Data Lake (30 Points)

fintech-data-lake/
├── raw/
│   ├── transactions/
│   ├── logs/
│   └── events/
├── processed/
│   ├── daily-reports/
│   └── aggregations/
├── archive/
│   └── compliance/
└── analytics/
    └── ml-data/

# Create S3 bucket for data lake
BUCKET_NAME="fintech-data-lake-$(date +%s)"
aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

# Enable encryption with KMS
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

# Block public access
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Enable server access logging
LOG_BUCKET="fintech-s3-logs-$(date +%s)"
aws s3api create-bucket --bucket $LOG_BUCKET --region us-east-1

aws s3api put-bucket-logging \
  --bucket $BUCKET_NAME \
  --bucket-logging-status '{
    "LoggingEnabled": {
      "TargetBucket": "'$LOG_BUCKET'",
      "TargetPrefix": "access-logs/"
    }
  }'

# Create folder structure
aws s3api put-object --bucket $BUCKET_NAME --key raw/transactions/
aws s3api put-object --bucket $BUCKET_NAME --key raw/logs/
aws s3api put-object --bucket $BUCKET_NAME --key raw/events/
aws s3api put-object --bucket $BUCKET_NAME --key processed/daily-reports/
aws s3api put-object --bucket $BUCKET_NAME --key processed/aggregations/
aws s3api put-object --bucket $BUCKET_NAME --key archive/compliance/
aws s3api put-object --bucket $BUCKET_NAME --key analytics/ml-data/

# Configure lifecycle policy for Intelligent-Tiering
aws s3api put-bucket-intelligent-tiering-configuration \
  --bucket $BUCKET_NAME \
  --id "EntireBucket" \
  --intelligent-tiering-configuration '{
    "Status": "Enabled",
    "Filter": {}
  }'

# Create lifecycle policy for transitions
aws s3api put-bucket-lifecycle-configuration \
  --bucket $BUCKET_NAME \
  --lifecycle-configuration '{
    "Rules": [{
      "Id": "ArchiveOldData",
      "Status": "Enabled",
      "Prefix": "archive/",
      "Transitions": [{
        "Days": 90,
        "StorageClass": "STANDARD_IA"
      }, {
        "Days": 180,
        "StorageClass": "GLACIER"
      }, {
        "Days": 365,
        "StorageClass": "DEEP_ARCHIVE"
      }]
    }, {
      "Id": "DeleteOldVersions",
      "Status": "Enabled",
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 90
      }
    }]
  }'

# Enable same-region replication (requires creating replication role first)
# Note: This is a simplified version - full replication setup requires IAM role creation


Task 4.4: ElastiCache Redis (30 Points)

# Create ElastiCache Subnet Group
aws elasticache create-cache-subnet-group \
  --cache-subnet-group-name fintech-redis-subnets \
  --cache-subnet-group-description "Subnets for FinTech Redis cluster" \
  --subnet-ids $DB_SUBNET_A $DB_SUBNET_B

# Create ElastiCache Security Group
REDIS_SG=$(aws ec2 create-security-group \
  --group-name fintech-redis-sg \
  --description "Security group for ElastiCache Redis" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)

# Allow ECS tasks to access Redis
aws ec2 authorize-security-group-ingress \
  --group-id $REDIS_SG \
  --protocol tcp \
  --port 6379 \
  --source-group $ECS_SG

# Create ElastiCache Redis Cluster
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


Task 4.5: Secrets Manager Configuration (30 Points)


# Note: Database credentials secret already created in Task 4.1
# To enable automatic rotation, use AWS managed rotation:
# aws secretsmanager enable-secret-rotation \
#   --secret-id fintech/db-credentials \
#   --rotation-rules AutomaticallyAfterDays=30

# Create secret for API keys
aws secretsmanager create-secret \
  --name fintech/api-keys \
  --description "API keys for external services" \
  --secret-string '{
    "stripe_api_key": "sk_live_xxxxx",
    "sendgrid_api_key": "SG.xxxxx"
  }' \
  --kms-key-id $KMS_KEY_ID

# Generate Redis auth token
REDIS_AUTH_TOKEN=$(openssl rand -base64 32)

# Create secret for Redis auth token
aws secretsmanager create-secret \
  --name fintech/redis-auth \
  --description "ElastiCache Redis authentication token" \
  --secret-string $REDIS_AUTH_TOKEN \
  --kms-key-id $KMS_KEY_ID

# Grant ECS task execution role access to secrets
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
        "arn:aws:secretsmanager:us-east-1:$ACCOUNT_ID:secret:fintech/*"
      ]
    }]
  }'

  ---

  Task 5.1: CloudWatch Configuration (40 Points)


# Create comprehensive CloudWatch Dashboard
aws cloudwatch put-dashboard \
  --dashboard-name FinTech-Operations \
  --dashboard-body '{
    "widgets": [
      {
        "type": "metric",
        "x": 0, "y": 0, "width": 8, "height": 6,
        "properties": {
          "title": "Transaction Processing Rate",
          "metrics": [
            ["FinTech", "TransactionsProcessed", {"stat": "Sum", "period": 60}],
            [".", "TransactionsFailed", {"stat": "Sum", "period": 60}]
          ],
          "region": "us-east-1"
        }
      },
      {
        "type": "metric",
        "x": 8, "y": 0, "width": 8, "height": 6,
        "properties": {
          "title": "API Latency (p99)",
          "metrics": [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "app/fintech-alb", {"stat": "p99"}]
          ]
        }
      },
      {
        "type": "metric",
        "x": 16, "y": 0, "width": 8, "height": 6,
        "properties": {
          "title": "Database Performance",
          "metrics": [
            ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", "fintech-cluster"],
            [".", "DatabaseConnections", ".", "."],
            [".", "AuroraReplicaLag", ".", "."]
          ]
        }
      },
      {
        "type": "alarm",
        "x": 0, "y": 6, "width": 24, "height": 4,
        "properties": {
          "title": "Active Alarms",
          "alarms": [
            "arn:aws:cloudwatch:us-east-1:ACCOUNT:alarm:high-error-rate",
            "arn:aws:cloudwatch:us-east-1:ACCOUNT:alarm:high-latency",
            "arn:aws:cloudwatch:us-east-1:ACCOUNT:alarm:db-connections",
            "arn:aws:cloudwatch:us-east-1:ACCOUNT:alarm:fraud-detection"
          ]
        }
      }
    ]
  }'

# Create Critical Alarms
aws cloudwatch put-metric-alarm \
  --alarm-name fintech-transaction-failures \
  --alarm-description "High transaction failure rate" \
  --metric-name TransactionsFailed \
  --namespace FinTech \
  --statistic Sum \
  --period 300 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions arn:aws:sns:us-east-1:$ACCOUNT_ID:fintech-alerts \
  --ok-actions arn:aws:sns:us-east-1:$ACCOUNT_ID:fintech-alerts \
  --treat-missing-data notBreaching


--

Task 5.2: X-Ray Tracing (30 Points)

Task 6.1: Reserved Capacity (25 Points)

Task 6.2: Cost Monitoring (25 Points)


Task 6.3: Optimization Recommendations (25 Points)


Task 7.1: High Availability & Backup (40 Points)


Task 7.2: Backup & Recovery Testing (35 Points)



