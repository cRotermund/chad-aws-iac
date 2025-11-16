#!/usr/bin/env bash
set -euo pipefail
# SSH into the nginx ingress node
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

NGINX_IP=$(terraform output -raw nginx_public_ip)
KEY_FILE="${HOME}/chad-k3s.pem"

echo "Connecting to nginx ingress at $NGINX_IP..."
ssh -i "$KEY_FILE" ec2-user@"$NGINX_IP"
