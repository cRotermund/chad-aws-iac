#!/usr/bin/env bash
# Source this script to set up AWS environment for Terraform
# Usage: source ./scripts/init.sh  (or . ./scripts/init.sh)

export AWS_PROFILE="terraform-iac"
export AWS_REGION="us-east-1"

echo "✓ AWS environment configured:"
echo "  AWS_PROFILE=$AWS_PROFILE"
echo "  AWS_REGION=$AWS_REGION"
echo ""
echo "You can now run terraform commands without specifying --profile"
