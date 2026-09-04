#!/usr/bin/env bash
set -euo pipefail
# Fetch kubeconfig from SSM and save locally.
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
REGION=$(terraform output -raw aws_region)
PROFILE="terraform-iac"
PARAM=$(terraform output -raw kubeconfig_ssm_parameter_name)
OUT_FILE="kubeconfig.yaml"

echo "Fetching kubeconfig from SSM parameter: $PARAM"
MSYS_NO_PATHCONV=1 aws --profile "$PROFILE" --region "$REGION" ssm get-parameter --name "$PARAM" --with-decryption --query Parameter.Value --output text > "$OUT_FILE"
chmod 600 "$OUT_FILE"
echo "Wrote kubeconfig to $OUT_FILE"
echo "Run: export KUBECONFIG=$(pwd)/$OUT_FILE"
