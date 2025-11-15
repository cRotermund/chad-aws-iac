# nginx-ingress Module

This module provisions a standalone EC2 instance running nginx as a load balancer and ingress controller for the K3s cluster.

## Purpose

- **Load Balancing:** Distributes incoming HTTP/HTTPS traffic to the K3s cluster
- **Static IP:** Associates your Elastic IP for a stable public endpoint
- **Ingress Management:** Acts as the entry point for all external traffic to your cluster
- **SSL Termination:** Can be configured to handle SSL/TLS certificates (requires manual setup)

## Architecture

```
Internet → Elastic IP → nginx EC2 → K3s Server (private IP)
```

The nginx instance sits outside the K3s cluster and proxies HTTP/HTTPS traffic to the K3s server node. This provides:
- A single, stable entry point with your static IP
- Separation of concerns (ingress separate from cluster)
- Flexibility to add SSL/TLS, custom routing, rate limiting, etc.

## Resources Created

- **Security Group:** Allows HTTP (80), HTTPS (443), optional SSH
- **EC2 Instance:** t4g.micro by default running Amazon Linux 2023 ARM
- **EIP Association:** Links your existing Elastic IP to the instance

## Configuration

The nginx configuration is deployed via user_data and includes:
- Basic reverse proxy setup to K3s server
- Upstream configuration pointing to K3s private IP
- Placeholder for HTTPS/SSL setup

### Customizing nginx Config

After deployment, SSH to the instance and edit:
```bash
sudo vi /etc/nginx/conf.d/k3s-proxy.conf
sudo systemctl reload nginx
```

For SSL certificates, you can:
1. Use Let's Encrypt with certbot
2. Upload your own certificates
3. Uncomment and configure the HTTPS server block in the config

### Adding More Backends

To load balance across multiple K3s nodes, edit the upstream block:
```nginx
upstream k3s_backend {
    server 10.0.1.10:80;  # K3s server
    server 10.0.1.20:80;  # K3s agent
}
```

## Inputs

| Variable | Description | Default |
|----------|-------------|---------|
| `vpc_id` | VPC ID where instance deploys | Required |
| `subnet_id` | Public subnet for the instance | Required |
| `instance_type` | EC2 instance type | `t4g.micro` |
| `eip_allocation_id` | Elastic IP allocation ID | Required |
| `k3s_server_private_ip` | Private IP of K3s server for proxy | Required |
| `key_name` | EC2 key pair for SSH | `""` (optional) |
| `ssh_allowed_cidrs` | CIDR blocks for SSH access | `[]` (optional) |
| `tags` | Resource tags | `{}` |

## Outputs

| Output | Description |
|--------|-------------|
| `security_group_id` | Security group ID |
| `instance_id` | EC2 instance ID |
| `private_ip` | Instance private IP |
| `public_ip` | Instance public IP (EIP) |

## Usage Example

```hcl
module "nginx_ingress" {
  source = "./modules/nginx-ingress"
  
  vpc_id                 = "vpc-12345678"
  subnet_id              = "subnet-12345678"
  eip_allocation_id      = "eipalloc-12345678"
  k3s_server_private_ip  = "10.0.1.100"
  key_name               = "my-keypair"
  ssh_allowed_cidrs      = ["1.2.3.4/32"]
  
  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Cost Considerations

- **t4g.micro:** ~$6/month (free tier eligible for 12 months)
- **EIP:** Free while associated to a running instance
- **Total:** Very cost-effective (~$6/month after free tier)

You can stop the instance when not in use to save costs (same as K3s nodes), but the EIP remains associated.
