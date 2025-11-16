#!/usr/bin/env bash
set -euo pipefail
# SSH into the K3s agent node
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

AGENT_IP=$(terraform output -raw k3s_agent_public_ip)
KEY_FILE="${HOME}/chad-k3s.pem"

echo "Connecting to K3s agent at $AGENT_IP..."
ssh -i "$KEY_FILE" ec2-user@"$AGENT_IP"
