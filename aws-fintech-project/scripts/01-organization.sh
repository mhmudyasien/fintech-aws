#!/bin/bash

# 01-organization.sh
# Task 1.1: AWS Organizations Setup
# Task 1.2: Tagging Strategy
# Task 1.3: Well-Architected Workload

echo "Starting Organization Setup..."

# Create Organization
# aws organizations create-organization --feature-set ALL

# Note: In a real environment, you'd capture the Root ID dynamically.
# PARENT_ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)

# Create OUs (Commented out effectively as placeholders for real IDs)
# SECURITY_OU_ID=$(aws organizations create-organizational-unit --parent-id $PARENT_ROOT_ID --name "Security" --query 'OrganizationalUnit.Id' --output text)
# WORKLOADS_OU_ID=$(aws organizations create-organizational-unit --parent-id $PARENT_ROOT_ID --name "Workloads" --query 'OrganizationalUnit.Id' --output text)

echo "Creating Policy Files..."

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

# Create SCPs
# aws organizations create-policy --name "DenyRootUserAccess" --description "Deny all actions for root user" --type SERVICE_CONTROL_POLICY --content file://deny-root-scp.json
# aws organizations create-policy --name "RegionRestriction" --description "Restrict to us-east-1" --type SERVICE_CONTROL_POLICY --content file://region-restriction-scp.json

# Tag Policy
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

# aws organizations create-policy --name "FinTechTagPolicy" --type TAG_POLICY --content file://tag-policy.json

# Config Rule
# aws configservice put-config-rule --config-rule '{"ConfigRuleName": "required-tags", "Source": {"Owner": "AWS", "SourceIdentifier": "REQUIRED_TAGS"}, "InputParameters": "{\"tag1Key\":\"Environment\",\"tag2Key\":\"Project\",\"tag3Key\":\"CostCenter\",\"tag4Key\":\"Owner\"}"}'

echo "Organization setup script logic defined. (Note: SCP creation commands commented out to prevent errors if not Organization Master)"
