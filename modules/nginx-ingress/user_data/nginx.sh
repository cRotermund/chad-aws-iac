#!/bin/bash
set -euo pipefail

# Install nginx
dnf install -y nginx

# Basic nginx config for load balancing to k3s
cat > /etc/nginx/conf.d/k3s-proxy.conf <<'EOF'
upstream k3s_backend {
    server ${k3s_server_private_ip}:80;
}

upstream argocd_backend {
    server ${k3s_server_private_ip}:30080;
}

# Default server for other domains
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    
    location / {
        proxy_pass http://k3s_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# ArgoCD server
server {
    listen 80;
    listen [::]:80;
    server_name admin.rotorlabs.io;
    
    # Redirect /argocd to /argocd/ with trailing slash
    location = /argocd {
        return 301 /argocd/;
    }
    
    location /argocd/ {
        proxy_pass http://argocd_backend/argocd/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support for ArgoCD
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# HTTPS placeholder - configure SSL certificates as needed
# server {
#     listen 443 ssl http2;
#     listen [::]:443 ssl http2;
#     server_name admin.rotorlabs.io;
#     
#     # ssl_certificate /etc/nginx/ssl/admin.rotorlabs.io.fullchain.pem;
#     # ssl_certificate_key /etc/nginx/ssl/admin.rotorlabs.io.key;
#     
#     # Modern SSL configuration
#     # ssl_protocols TLSv1.2 TLSv1.3;
#     # ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
#     # ssl_prefer_server_ciphers off;
#     
#     # Redirect /argocd to /argocd/ with trailing slash
#     location = /argocd {
#         return 301 /argocd/;
#     }
#     
#     location /argocd/ {
#         proxy_pass http://argocd_backend/argocd/;
#         proxy_set_header Host $host;
#         proxy_set_header X-Real-IP $remote_addr;
#         proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
#         proxy_set_header X-Forwarded-Proto $scheme;
#         
#         # WebSocket support
#         proxy_http_version 1.1;
#         proxy_set_header Upgrade $http_upgrade;
#         proxy_set_header Connection "upgrade";
#     }
# }
EOF

# Enable and start nginx
systemctl enable nginx
systemctl start nginx

echo "nginx installed and configured" > /var/log/nginx-install.log
