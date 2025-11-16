#!/usr/bin/env bash
set -euo pipefail
# Fetch ArgoCD admin password from SSM and display it.
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "Fetching ArgoCD admin password..."
terraform output -raw argocd_admin_password

echo ""
echo ""
echo "Username: admin"
echo "ArgoCD UI: http://admin.rotorlabs.io/argocd"
