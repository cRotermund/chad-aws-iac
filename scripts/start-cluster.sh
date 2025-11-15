#!/usr/bin/env bash
set -euo pipefail
# Starts k3s EC2 instances using Terraform outputs.
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
SERVER_ID=$(terraform output -raw k3s_server_instance_id)
AGENT_ID=$(terraform output -raw k3s_agent_instance_id)
REGION=$(terraform output -raw aws_region)
PROFILE="terraform-iac"

echo "Starting instances: $SERVER_ID $AGENT_ID in $REGION"
aws --profile "$PROFILE" --region "$REGION" ec2 start-instances --instance-ids "$SERVER_ID" "$AGENT_ID" >/dev/null
aws --profile "$PROFILE" --region "$REGION" ec2 wait instance-running --instance-ids "$SERVER_ID" "$AGENT_ID"
echo "Instances are starting. Waiting for status OK..."
aws --profile "$PROFILE" --region "$REGION" ec2 wait instance-status-ok --instance-ids "$SERVER_ID" "$AGENT_ID"
echo "Cluster instances running. Public IPs:"
terraform output k3s_server_public_ip
terraform output k3s_agent_public_ip
