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

# Install K3s in server mode
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644 --token $TOKEN" sh -
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
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
cp /etc/rancher/k3s/k3s.yaml /tmp/kubeconfig
sed -i "s/127.0.0.1/$PUBLIC_IP/" /tmp/kubeconfig
aws ssm put-parameter --name ${ssm_kubeconfig_name} --type SecureString --overwrite --value "$(cat /tmp/kubeconfig)" || true
echo "Kubeconfig uploaded to SSM" >> /var/log/k3s-install.log

# Install ArgoCD
echo "Installing ArgoCD..." >> /var/log/k3s-install.log
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Create argocd namespace
kubectl create namespace argocd || true

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
echo "Waiting for ArgoCD to be ready..." >> /var/log/k3s-install.log
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd || true

# Configure ArgoCD to use /argocd base path and expose via NodePort
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.basehref":"/argocd","server.rootpath":"/argocd","server.insecure":"true"}}'

# Patch argocd-server service to use NodePort on port 30080
kubectl patch service argocd-server -n argocd --type merge -p '{"spec":{"type":"NodePort","ports":[{"name":"http","port":80,"protocol":"TCP","targetPort":8080,"nodePort":30080}]}}'

# Restart argocd-server to pick up config changes
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd --timeout=300s || true

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
	aws ssm put-parameter --name ${ssm_argocd_password_name} --type SecureString --overwrite --value "$ARGOCD_PASSWORD"
	echo "ArgoCD installed and password uploaded to SSM" >> /var/log/k3s-install.log
else
	echo "ERROR: Failed to retrieve ArgoCD password" >> /var/log/k3s-install.log
fi
