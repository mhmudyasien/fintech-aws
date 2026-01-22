#!/bin/bash
# 02-vpc.sh
# Task 2.1: VPC Architecture

echo "Starting VPC Setup..."

# Create Production VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=fintech-prod-vpc},{Key=Environment,Value=Production}]' \
  --query 'Vpc.VpcId' --output text)

echo "Created VPC: $VPC_ID"
export VPC_ID

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

# Export Subnet IDs for later scripts
export PUBLIC_SUBNET_A PUBLIC_SUBNET_B
export PRIVATE_SUBNET_A PRIVATE_SUBNET_B
export DB_SUBNET_A DB_SUBNET_B

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

echo "Waiting for NAT Gateway..."
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

# Save variables to state file for subsequent scripts
cat << EOF > .env_state
export VPC_ID=$VPC_ID
export PUBLIC_SUBNET_A=$PUBLIC_SUBNET_A
export PUBLIC_SUBNET_B=$PUBLIC_SUBNET_B
export PRIVATE_SUBNET_A=$PRIVATE_SUBNET_A
export PRIVATE_SUBNET_B=$PRIVATE_SUBNET_B
export DB_SUBNET_A=$DB_SUBNET_A
export DB_SUBNET_B=$DB_SUBNET_B
export VPC_ENDPOINT_SG=$VPC_ENDPOINT_SG
EOF

echo "VPC Setup Complete. State saved to .env_state"
