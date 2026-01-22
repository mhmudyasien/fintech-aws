#!/bin/bash
# 02-vpc.sh
# Production-ready VPC/Networking setup
# Idempotent: Checks for existing resources before creating.

set -e

PROJECT="fintech"
ENV="production"
VPC_NAME="${PROJECT}-prod-vpc"
REGION="us-east-1"
CIDR_BLOCK="10.0.0.0/16"

# Helper function to check for resource existence by tag Name
get_resource_id() {
    local resource_type=$1
    local name=$2
    aws ec2 describe-${resource_type}s \
        --filters "Name=tag:Name,Values=${name}" "Name=item-status,Values=available,associated" 2>/dev/null | \
        jq -r ".${resource_type^}s[0].${resource_type^}Id" | grep -v "null" || echo ""
}

# Special handler since 'describe-vpcs' uses 'Vpcs' not 'Vpcss'
get_vpc_id() {
     aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$1" --query "Vpcs[0].VpcId" --output text | grep -v "None" || echo ""
}

get_subnet_id() {
    aws ec2 describe-subnets --filters "Name=tag:Name,Values=$1" --query "Subnets[0].SubnetId" --output text | grep -v "None" || echo ""
}

get_igw_id() {
    aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=$1" --query "InternetGateways[0].InternetGatewayId" --output text | grep -v "None" || echo ""
}

get_nat_id() {
    aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=$1" "Name=state,Values=available" --query "NatGateways[0].NatGatewayId" --output text | grep -v "None" || echo ""
}

echo "--- Starting VPC Setup ($VPC_NAME) ---"

# 1. VPC
VPC_ID=$(get_vpc_id $VPC_NAME)
if [ -z "$VPC_ID" ]; then
    echo "Creating VPC..."
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block $CIDR_BLOCK \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$VPC_NAME},{Key=Environment,Value=$ENV},{Key=Project,Value=$PROJECT}]" \
        --query 'Vpc.VpcId' --output text)
else
    echo "VPC exists: $VPC_ID"
fi

# Enable DNS
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames '{"Value":true}'
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support '{"Value":true}'

# 2. Internet Gateway
IGW_NAME="${PROJECT}-igw"
IGW_ID=$(get_igw_id $IGW_NAME)
if [ -z "$IGW_ID" ]; then
    echo "Creating Internet Gateway..."
    IGW_ID=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$IGW_NAME},{Key=Project,Value=$PROJECT}]" \
        --query 'InternetGateway.InternetGatewayId' --output text)
    aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
else
    echo "IGW exists: $IGW_ID"
fi

# 3. Subnets
AZS=($(aws ec2 describe-availability-zones --region $REGION --query 'AvailabilityZones[0:2].ZoneName' --output text))
AZ_A=${AZS[0]}
AZ_B=${AZS[1]}

# Public A
PUB_SUBNET_A_NAME="${PROJECT}-public-subnet-1a"
PUB_SUBNET_A=$(get_subnet_id $PUB_SUBNET_A_NAME)
if [ -z "$PUB_SUBNET_A" ]; then
    echo "Creating Public Subnet A..."
    PUB_SUBNET_A=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone $AZ_A \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$PUB_SUBNET_A_NAME},{Key=Type,Value=Public}]" \
        --query 'Subnet.SubnetId' --output text)
    aws ec2 modify-subnet-attribute --subnet-id $PUB_SUBNET_A --map-public-ip-on-launch
else
    echo "Public Subnet A exists: $PUB_SUBNET_A"
fi

# Public B
PUB_SUBNET_B_NAME="${PROJECT}-public-subnet-1b"
PUB_SUBNET_B=$(get_subnet_id $PUB_SUBNET_B_NAME)
if [ -z "$PUB_SUBNET_B" ]; then
    echo "Creating Public Subnet B..."
    PUB_SUBNET_B=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone $AZ_B \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$PUB_SUBNET_B_NAME},{Key=Type,Value=Public}]" \
        --query 'Subnet.SubnetId' --output text)
    aws ec2 modify-subnet-attribute --subnet-id $PUB_SUBNET_B --map-public-ip-on-launch
else
    echo "Public Subnet B exists: $PUB_SUBNET_B"
fi

# Private App A
PRIV_SUBNET_A_NAME="${PROJECT}-private-app-subnet-1a"
PRIV_SUBNET_A=$(get_subnet_id $PRIV_SUBNET_A_NAME)
if [ -z "$PRIV_SUBNET_A" ]; then
    echo "Creating Private App Subnet A..."
    PRIV_SUBNET_A=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.10.0/24 --availability-zone $AZ_A \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$PRIV_SUBNET_A_NAME},{Key=Type,Value=Private}]" \
        --query 'Subnet.SubnetId' --output text)
else
    echo "Private App Subnet A exists: $PRIV_SUBNET_A"
fi

# Private App B
PRIV_SUBNET_B_NAME="${PROJECT}-private-app-subnet-1b"
PRIV_SUBNET_B=$(get_subnet_id $PRIV_SUBNET_B_NAME)
if [ -z "$PRIV_SUBNET_B" ]; then
    echo "Creating Private App Subnet B..."
    PRIV_SUBNET_B=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.11.0/24 --availability-zone $AZ_B \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$PRIV_SUBNET_B_NAME},{Key=Type,Value=Private}]" \
        --query 'Subnet.SubnetId' --output text)
else
    echo "Private App Subnet B exists: $PRIV_SUBNET_B"
fi

# 4. NAT Gateway (Single NAT for simplicity/cost, usually one per AZ for HA)
NAT_NAME="${PROJECT}-nat-gw"
NAT_GW_ID=$(get_nat_id $NAT_NAME)
if [ -z "$NAT_GW_ID" ]; then
    echo "Allocating EIP for NAT..."
    EIP_ALLOC=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
    echo "Creating NAT Gateway (this may take a minute)..."
    NAT_GW_ID=$(aws ec2 create-nat-gateway \
        --subnet-id $PUB_SUBNET_A \
        --allocation-id $EIP_ALLOC \
        --tag-specifications "ResourceType=nat-gateway,Tags=[{Key=Name,Value=$NAT_NAME}]" \
        --query 'NatGateway.NatGatewayId' --output text)
    
    echo "Waiting for NAT Gateway to be available..."
    aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW_ID
else
    echo "NAT Gateway exists: $NAT_GW_ID"
fi

# 5. Route Tables
PUB_RT_NAME="${PROJECT}-public-rt"
PUB_RT_ID=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=$PUB_RT_NAME" --query "RouteTables[0].RouteTableId" --output text | grep -v "None" || echo "")

if [ -z "$PUB_RT_ID" ]; then
    echo "Creating Public Route Table..."
    PUB_RT_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$PUB_RT_NAME}]" \
        --query 'RouteTable.RouteTableId' --output text)
    
    aws ec2 create-route --route-table-id $PUB_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
else
    echo "Public Route Table exists: $PUB_RT_ID"
fi

# Associate Public Subnets
aws ec2 associate-route-table --subnet-id $PUB_SUBNET_A --route-table-id $PUB_RT_ID || true
aws ec2 associate-route-table --subnet-id $PUB_SUBNET_B --route-table-id $PUB_RT_ID || true

PRIV_RT_NAME="${PROJECT}-private-rt"
PRIV_RT_ID=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=$PRIV_RT_NAME" --query "RouteTables[0].RouteTableId" --output text | grep -v "None" || echo "")

if [ -z "$PRIV_RT_ID" ]; then
    echo "Creating Private Route Table..."
    PRIV_RT_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$PRIV_RT_NAME}]" \
        --query 'RouteTable.RouteTableId' --output text)
    
    aws ec2 create-route --route-table-id $PRIV_RT_ID --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW_ID
else
    echo "Private Route Table exists: $PRIV_RT_ID"
fi

# Associate Private Subnets
aws ec2 associate-route-table --subnet-id $PRIV_SUBNET_A --route-table-id $PRIV_RT_ID || true
aws ec2 associate-route-table --subnet-id $PRIV_SUBNET_B --route-table-id $PRIV_RT_ID || true

# 6. Save State
echo "Saving state to .env_state..."
cat > .env_state <<EOF
export VPC_ID=$VPC_ID
export PUBLIC_SUBNET_A=$PUB_SUBNET_A
export PUBLIC_SUBNET_B=$PUB_SUBNET_B
export PRIVATE_SUBNET_A=$PRIV_SUBNET_A
export PRIVATE_SUBNET_B=$PRIV_SUBNET_B
export NAT_GW_ID=$NAT_GW_ID
EOF

echo "--- VPC Setup Complete ---"
