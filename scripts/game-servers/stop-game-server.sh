#!/usr/bin/env bash
set -euo pipefail
# Stops the Satisfactory EC2 instance using game-servers Terraform outputs.
# This is a hard EC2 stop. Save the game first (in-game Server Manager, or the
# server console's server.SaveGame command) so progress since the last autosave is kept.
# The Elastic IP stays associated, so the public IP is unchanged on the next start.
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR/game-servers"

INSTANCE_ID="$(terraform output -raw satisfactory_instance_id 2>/dev/null)" || {
  echo "Could not read satisfactory_instance_id. Has the game-servers stack been applied?" >&2
  exit 1
}
REGION="${AWS_REGION:-us-east-1}"
PROFILE="${AWS_PROFILE:-terraform-iac}"

echo "Stopping instance: $INSTANCE_ID in $REGION"
echo "Reminder: save the game first if you have not saved recently."
aws --profile "$PROFILE" --region "$REGION" ec2 stop-instances --instance-ids "$INSTANCE_ID" >/dev/null
aws --profile "$PROFILE" --region "$REGION" ec2 wait instance-stopped --instance-ids "$INSTANCE_ID"
echo "Instance stopped. The Elastic IP remains allocated and is still billed while allocated."
