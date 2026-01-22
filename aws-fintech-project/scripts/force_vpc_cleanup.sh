#!/bin/bash
# force_vpc_cleanup.sh
# Automates the difficult task of tearing down the old 'fintech-prod-vpc' 
# to free up quota for Terraform.

set -e

VPC_NAME="fintech-prod-vpc"
REGION="us-east-1"
export AWS_DEFAULT_REGION=$REGION
export AWS_REGION=$REGION

echo "--- Force Cleanup for $VPC_NAME ---"

# Get VPC ID
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[0].VpcId" --output text)

if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
    echo "VPC $VPC_NAME not found. You might have other VPCs consuming your quota."
    echo "Listing all VPCs:"
    aws ec2 describe-vpcs --query "Vpcs[].{ID:VpcId,Name:Tags[?Key=='Name'].Value|[0],CIDR:CidrBlock}" --output table
    exit 0
fi

echo "Found VPC: $VPC_ID"
echo "Deleting dependencies..."

# 1. Delete NAT Gateways
echo "Checking NAT Gateways..."
NAT_IDS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" --query "NatGateways[*].NatGatewayId" --output text)
if [ -n "$NAT_IDS" ] && [ "$NAT_IDS" != "None" ]; then
    for nat in $NAT_IDS; do
        echo "Deleting NAT Gateway: $nat"
        aws ec2 delete-nat-gateway --nat-gateway-id $nat
    done
    echo "Waiting for NAT Gateways to delete (this takes a minute)..."
    while true; do
        COUNT=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=pending,available,deleting" --query "length(NatGateways)" --output text)
        if [ "$COUNT" == "0" ]; then break; fi
        echo "Still waiting... ($COUNT remaining)"
        sleep 10
    done
fi

# 2. Delete VPC Endpoints
echo "Checking VPC Endpoints..."
VPCE_IDS=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --query "VpcEndpoints[*].VpcEndpointId" --output text)
if [ -n "$VPCE_IDS" ] && [ "$VPCE_IDS" != "None" ]; then
    for vpce in $VPCE_IDS; do
        echo "Deleting VPC Endpoint: $vpce"
        aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $vpce
    done
fi

# 3. Release EIPs (Optimization: only release unassociated ones or ones known to be ours? 
# For safety, we skip blind EIP release to avoid deleting user's other IPs, but usually NAT GW release disassociates them.)

# 4. Detach & Delete IGW
echo "Checking Internet Gateways..."
IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[0].InternetGatewayId" --output text)
if [ -n "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
    echo "Detaching IGW: $IGW_ID"
    aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
    echo "Deleting IGW: $IGW_ID"
    aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID
fi

# 5. Delete Subnets
echo "Deleting Subnets..."
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text)
if [ -n "$SUBNET_IDS" ] && [ "$SUBNET_IDS" != "None" ]; then
    for subnet in $SUBNET_IDS; do
        echo "Deleting Subnet: $subnet"
        aws ec2 delete-subnet --subnet-id $subnet
    done
fi

# 6. Delete Route Tables (Main RT cannot be deleted)
echo "Deleting custom Route Tables..."
RT_IDS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query "RouteTables[?Associations==\`[]\`].RouteTableId" --output text)
if [ -n "$RT_IDS" ] && [ "$RT_IDS" != "None" ]; then
    for rt in $RT_IDS; do
        # Verify it's not main
        IS_MAIN=$(aws ec2 describe-route-tables --route-table-ids $rt --query "RouteTables[0].Associations[?Main==\`true\`]" --output text)
        if [ -z "$IS_MAIN" ] || [ "$IS_MAIN" == "None" ]; then
             echo "Deleting Route Table: $rt"
             aws ec2 delete-route-table --route-table-id $rt
        fi
    done
fi

# 7. Delete Security Groups (Default cannot be deleted)
echo "Deleting Security Groups..."
SG_IDS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
if [ -n "$SG_IDS" ] && [ "$SG_IDS" != "None" ]; then
    for sg in $SG_IDS; do
        echo "Deleting Security Group: $sg"
        aws ec2 delete-security-group --group-id $sg
    done
fi

# 8. Delete VPC
echo "Deleting VPC: $VPC_ID"
aws ec2 delete-vpc --vpc-id $VPC_ID

echo "--- Cleanup Complete. VPC Quota freed. ---"
