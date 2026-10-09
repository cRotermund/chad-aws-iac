#!/bin/bash
set -euo pipefail

# Install AWS CLI if not present
command -v aws >/dev/null 2>&1 || (dnf install -y awscli || yum install -y awscli)

# Wait for IAM instance profile credentials to be available
echo "Waiting for IAM credentials to be available..." > /var/log/k3s-install.log
for i in {1..30}; do
	if aws sts get-caller-identity &>/dev/null; then
		echo "IAM credentials available!" >> /var/log/k3s-install.log
		break
	fi
	echo "Waiting for IAM credentials... attempt $i/30" >> /var/log/k3s-install.log
	sleep 5
done

# Fetch K3s token from SSM Parameter Store
TOKEN=$(aws ssm get-parameter --name ${ssm_token_name} --with-decryption --query Parameter.Value --output text)

# Use the configured Elastic IP when available. Otherwise, obtain the
# instance's current public IP through IMDSv2 before creating the certificate.
PUBLIC_IP="${server_public_ip}"
if [ -z "$PUBLIC_IP" ]; then
	IMDS_TOKEN=$(curl --fail --silent --show-error \
		-X PUT \
		-H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
		http://169.254.169.254/latest/api/token)
	PUBLIC_IP=$(curl --fail --silent --show-error \
		-H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
		http://169.254.169.254/latest/meta-data/public-ipv4)
fi
if [ -z "$PUBLIC_IP" ]; then
	echo "ERROR: Could not determine the server public IP" >> /var/log/k3s-install.log
	exit 1
fi

# Install K3s in server mode. The discovery and JWKS endpoints are public
# OIDC metadata endpoints, while other Kubernetes API access remains governed
# by the normal authentication and authorization configuration.
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644 --token $TOKEN --tls-san $PUBLIC_IP --kube-apiserver-arg=service-account-issuer=${service_account_issuer} --kube-apiserver-arg=service-account-jwks-uri=${service_account_issuer}/openid/v1/jwks --kube-apiserver-arg=anonymous-auth=true" sh -
echo "k3s server installed (SSM token)" >> /var/log/k3s-install.log

# Wait for k3s to be ready (kubeconfig file exists and is valid)
echo "Waiting for k3s to be ready..." >> /var/log/k3s-install.log
for i in {1..30}; do
	if [ -f /etc/rancher/k3s/k3s.yaml ] && kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml get nodes &>/dev/null; then
		echo "k3s is ready!" >> /var/log/k3s-install.log
		break
	fi
	echo "Waiting for k3s... attempt $i/30" >> /var/log/k3s-install.log
	sleep 10
done

# Export kubeconfig to SSM so Terraform can read it later.
# Replace 127.0.0.1 with this node's public IP for external access.
cp /etc/rancher/k3s/k3s.yaml /tmp/kubeconfig
sed -i "s/127.0.0.1/$PUBLIC_IP/" /tmp/kubeconfig
if aws ssm put-parameter --name ${ssm_kubeconfig_name} --type SecureString --overwrite --value "$(cat /tmp/kubeconfig)"; then
	echo "Kubeconfig uploaded to SSM" >> /var/log/k3s-install.log
else
	echo "ERROR: Failed to upload kubeconfig to SSM (${ssm_kubeconfig_name})" >> /var/log/k3s-install.log
fi

# Install ArgoCD
echo "Installing ArgoCD..." >> /var/log/k3s-install.log
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Create argocd namespace
kubectl create namespace argocd || true

# Install ArgoCD (use server-side apply to avoid CRD annotation size limit)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side

# Wait for ArgoCD to be ready
echo "Waiting for ArgoCD to be ready..." >> /var/log/k3s-install.log
if kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd; then
	echo "ArgoCD server is ready" >> /var/log/k3s-install.log
else
	echo "WARNING: ArgoCD server did not become available within timeout" >> /var/log/k3s-install.log
fi

# Configure ArgoCD to use /argocd base path and expose via NodePort
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.basehref":"/argocd","server.rootpath":"/argocd","server.insecure":"true"}}'

# Patch argocd-server service to use NodePort on port 30080
kubectl patch service argocd-server -n argocd --type merge -p '{"spec":{"type":"NodePort","ports":[{"name":"http","port":80,"protocol":"TCP","targetPort":8080,"nodePort":30080}]}}'

# Restart argocd-server to pick up config changes
kubectl rollout restart deployment argocd-server -n argocd
if kubectl rollout status deployment argocd-server -n argocd --timeout=300s; then
	echo "ArgoCD server restarted successfully" >> /var/log/k3s-install.log
else
	echo "WARNING: ArgoCD server rollout did not complete within timeout" >> /var/log/k3s-install.log
fi

# Wait for ArgoCD initial admin secret to be created
echo "Waiting for ArgoCD admin secret..." >> /var/log/k3s-install.log
for i in {1..30}; do
	if kubectl -n argocd get secret argocd-initial-admin-secret &>/dev/null; then
		echo "ArgoCD admin secret found!" >> /var/log/k3s-install.log
		break
	fi
	echo "Waiting for ArgoCD admin secret... attempt $i/30" >> /var/log/k3s-install.log
	sleep 10
done

# Get initial admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

# Store ArgoCD password in SSM (only if we got a password)
if [ -n "$ARGOCD_PASSWORD" ]; then
	if aws ssm put-parameter --name ${ssm_argocd_password_name} --type SecureString --overwrite --value "$ARGOCD_PASSWORD"; then
		echo "ArgoCD password uploaded to SSM" >> /var/log/k3s-install.log
	else
		echo "ERROR: Failed to upload ArgoCD password to SSM (${ssm_argocd_password_name})" >> /var/log/k3s-install.log
	fi
else
	echo "ERROR: Failed to retrieve ArgoCD password" >> /var/log/k3s-install.log
fi
