#!/usr/bin/env bash
set -euo pipefail
# Starts the Satisfactory EC2 instance using game-servers Terraform outputs.
# The Elastic IP stays associated across stop/start, so the public IP does not change.
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR/game-servers"

INSTANCE_ID="$(terraform output -raw satisfactory_instance_id 2>/dev/null)" || {
  echo "Could not read satisfactory_instance_id. Has the game-servers stack been applied?" >&2
  exit 1
}
REGION="${AWS_REGION:-us-east-1}"
PROFILE="${AWS_PROFILE:-terraform-iac}"

echo "Starting instance: $INSTANCE_ID in $REGION"
aws --profile "$PROFILE" --region "$REGION" ec2 start-instances --instance-ids "$INSTANCE_ID" >/dev/null
aws --profile "$PROFILE" --region "$REGION" ec2 wait instance-running --instance-ids "$INSTANCE_ID"
echo "Instance is running. Waiting for status checks..."
aws --profile "$PROFILE" --region "$REGION" ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID"
echo "Instance is ready. Public IP: $(terraform output -raw satisfactory_public_ip)"
echo "Run scripts/game-servers/healthcheck-game-servers.sh to verify the game server."
