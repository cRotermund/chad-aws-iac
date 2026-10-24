#!/usr/bin/env bash
set -euo pipefail
# Starts k3s and nginx EC2 instances using Terraform outputs.
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
SERVER_ID=$(terraform output -raw k3s_server_instance_id)
AGENT_ID=$(terraform output -raw k3s_agent_instance_id)
NGINX_ID=$(terraform output -raw nginx_instance_id)
REGION=$(terraform output -raw aws_region)
PROFILE="terraform-iac"

echo "Starting instances: $SERVER_ID $AGENT_ID $NGINX_ID in $REGION"
aws --profile "$PROFILE" --region "$REGION" ec2 start-instances --instance-ids "$SERVER_ID" "$AGENT_ID" "$NGINX_ID" >/dev/null
aws --profile "$PROFILE" --region "$REGION" ec2 wait instance-running --instance-ids "$SERVER_ID" "$AGENT_ID" "$NGINX_ID"
echo "Instances are starting. Waiting for status OK..."
aws --profile "$PROFILE" --region "$REGION" ec2 wait instance-status-ok --instance-ids "$SERVER_ID" "$AGENT_ID" "$NGINX_ID"
echo "All instances running. Public IPs:"
echo "nginx: $(terraform output -raw nginx_public_ip)"
echo "K3s server: $(terraform output -raw k3s_server_public_ip)"
echo "K3s agent: $(terraform output -raw k3s_agent_public_ip)"
