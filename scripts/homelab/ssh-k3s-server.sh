#!/usr/bin/env bash
set -euo pipefail
# SSH into the K3s server node
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SERVER_IP=$(terraform output -raw k3s_server_public_ip)
KEY_FILE="${HOME}/chad-k3s.pem"

echo "Connecting to K3s server at $SERVER_IP..."
ssh -i "$KEY_FILE" ec2-user@"$SERVER_IP"
