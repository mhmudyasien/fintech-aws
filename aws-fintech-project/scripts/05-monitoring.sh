#!/bin/bash
# 05-monitoring.sh
# Task 5.1: CloudWatch Configuration

if [ -f .env_state ]; then
  source .env_state
else
  echo "Error: .env_state not found."
  exit 1
fi

echo "Starting Monitoring Setup..."

# Create Dashboard
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
      }
    ]
  }'

echo "CloudWatch Dashboard 'FinTech-Operations' created."

# Note: Alarm creation requires an SNS Topic ARN which wasn't explicitly created in previous steps.
# In a real script we would create the SNS topic first.
# echo "Creating Alarms..."
