#!/bin/bash
set -euo pipefail

# The certificate and key are provisioned out-of-band into SSM SecureString
# parameters. This keeps the private key out of Terraform and user_data.
dnf install -y nginx
if ! command -v amazon-ssm-agent >/dev/null 2>&1; then
    dnf install -y amazon-ssm-agent
fi
command -v aws >/dev/null 2>&1 || { echo "AWS CLI is required to retrieve TLS parameters" >&2; exit 1; }
systemctl enable --now amazon-ssm-agent

install -d -m 700 /etc/nginx/ssl
umask 077
aws ssm get-parameter \
    --name '${tls_certificate_parameter}' \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text > /etc/nginx/ssl/rotorlabs.crt
aws ssm get-parameter \
    --name '${tls_ca_bundle_parameter}' \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text > /etc/nginx/ssl/rotorlabs.ca-bundle
cat /etc/nginx/ssl/rotorlabs.crt /etc/nginx/ssl/rotorlabs.ca-bundle > /etc/nginx/ssl/rotorlabs.fullchain.pem
aws ssm get-parameter \
    --name '${tls_private_key_parameter}' \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text > /etc/nginx/ssl/rotorlabs.key
chmod 600 /etc/nginx/ssl/rotorlabs.key

cat > /etc/nginx/conf.d/k3s-proxy.conf <<'EOF'
upstream k3s_backend {
    server ${k3s_server_private_ip}:80;
}

upstream argocd_backend {
    server ${k3s_server_private_ip}:30080;
}

upstream k3s_api_backend {
    server ${k3s_server_private_ip}:6443;
}

# Redirect every HTTP host to HTTPS while preserving the requested URI.
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 301 https://$host$request_uri;
}

# ArgoCD is exposed below /argocd on the admin host.
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name admin.rotorlabs.io;

    ssl_certificate /etc/nginx/ssl/rotorlabs.fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/rotorlabs.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    location = /argocd {
        return 301 /argocd/;
    }

    location /argocd/ {
        proxy_pass http://argocd_backend/argocd/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# The public OIDC issuer is served by the Kubernetes API server. TLS terminates
# at nginx, while this private hop uses the API server's native HTTPS endpoint.
# Certificate verification is intentionally disabled because the API server
# certificate is private to the cluster and access is restricted by security
# groups.
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name apis.rotorlabs.io;

    ssl_certificate /etc/nginx/ssl/rotorlabs.fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/rotorlabs.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    location = /aws-oidc/.well-known/openid-configuration {
        proxy_pass https://k3s_api_backend/.well-known/openid-configuration;
        proxy_ssl_verify off;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    location = /aws-oidc/openid/v1/jwks {
        proxy_pass https://k3s_api_backend/openid/v1/jwks;
        proxy_ssl_verify off;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    # Preserve the existing API ingress behavior for non-OIDC paths.
    location / {
        proxy_pass http://k3s_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}

# Applications are routed to the K3s HTTP ingress backend.
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name apps.rotorlabs.io;

    ssl_certificate /etc/nginx/ssl/rotorlabs.fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/rotorlabs.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://k3s_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}

# Reject unknown HTTPS hosts rather than routing them into the cluster.
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;
    ssl_certificate /etc/nginx/ssl/rotorlabs.fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/rotorlabs.key;
    return 444;
}
EOF

nginx -t
systemctl enable nginx
systemctl restart nginx

echo "nginx installed and configured with TLS termination" > /var/log/nginx-install.log
