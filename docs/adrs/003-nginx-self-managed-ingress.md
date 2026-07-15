# ADR 003: Self-Managed nginx as Ingress

- **Status:** Accepted
- **Date:** 2025-07

## Context

External traffic needs a stable entry point into the K3s cluster. The ingress solution must:

- Provide a fixed, predictable endpoint (the K3s server's public IP may change)
- Proxy HTTP/HTTPS traffic to K3s workloads
- Support path-based routing (e.g., `/argocd` to ArgoCD)
- Remain cost-effective for a personal/learning cluster

## Decision

Use a **self-managed nginx EC2 instance** with a pre-existing Elastic IP as the ingress layer, placed in front of the K3s cluster.

Nginx is configured at boot via user_data to proxy:
- Default traffic → K3s server (port 80)
- `admin.rotorlabs.io/argocd` → ArgoCD via K3s NodePort 30080

### Alternatives Considered

| Option | Pros | Cons |
|--------|------|------|
| **Self-managed nginx** (chosen) | Full control; no hourly LB cost; static EIP survives instance recreation; simple configuration | Manual SSL config; single point of failure; requires OS patching |
| AWS Application Load Balancer | Fully managed; automatic SSL via ACM; WAF integration | ~$20+/month base cost; EIP not natively supported (requires Global Accelerator); overkill for personal use |
| AWS Network Load Balancer | Layer 4; static IP via EIP | No path-based routing; can't handle `/argocd` prefix proxying |
| Cloudflare Tunnel | Free; no open ports required | Introduces external dependency; requires `cloudflared` daemon |
| K3s built-in Traefik + NodePort | No additional instance | Server IP may change; no clean SSL termination point |

## Consequences

- **Positive:** Static Elastic IP provides a stable endpoint that survives cluster recreation
- **Positive:** Path-based routing enables multiple services behind a single IP/port
- **Positive:** Cost-effective — only paying for the EC2 t4g.micro instance, no hourly LB charges
- **Negative:** Single point of failure — if the nginx instance goes down, all inbound traffic is blocked
- **Negative:** SSL termination must be configured manually (Certbot + Let's Encrypt)
- **Negative:** Requires OS-level maintenance (patching, nginx updates)