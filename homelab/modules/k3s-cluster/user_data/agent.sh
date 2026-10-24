#!/bin/bash
set -euo pipefail

# Install AWS CLI if not present
command -v aws >/dev/null 2>&1 || (dnf install -y awscli || yum install -y awscli)

# Wait for IAM instance profile credentials to be available
echo "Waiting for IAM credentials to be available..." > /var/log/k3s-agent-install.log
for i in {1..30}; do
	if aws sts get-caller-identity &>/dev/null; then
		echo "IAM credentials available!" >> /var/log/k3s-agent-install.log
		break
	fi
	echo "Waiting for IAM credentials... attempt $i/30" >> /var/log/k3s-agent-install.log
	sleep 5
done

# Fetch K3s token from SSM Parameter Store
TOKEN=$(aws ssm get-parameter --name ${ssm_token_name} --with-decryption --query Parameter.Value --output text)

# Install K3s in agent mode, connecting to the server
echo "Installing k3s agent..." >> /var/log/k3s-agent-install.log
curl -sfL https://get.k3s.io | K3S_URL="https://${k3s_server_private_ip}:6443" K3S_TOKEN="$TOKEN" sh -
echo "k3s agent installed (SSM token)" >> /var/log/k3s-agent-install.log