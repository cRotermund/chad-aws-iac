# AWS Infrastructure as Code - K3s Cluster

This repository manages a lightweight **K3s Kubernetes cluster** running on AWS EC2 instances using Terraform. The infrastructure adopts existing VPC/networking resources and provisions a two-node K3s cluster (one server, one agent) with an nginx ingress/load balancer node, all configured via SSM Parameter Store.

## Overview

**What this does:**
- Provisions a 2-node K3s cluster (1 server + 1 agent) on ARM-based EC2 instances (`t4g.medium` by default)
- **nginx ingress node** with a pre-existing Elastic IP for load balancing and ingress management
- Uses existing VPC and public subnets (no new network infrastructure created)
- Stores K3s cluster join token, kubeconfig, and ArgoCD admin password securely in AWS SSM Parameter Store
- Configures a stable Kubernetes service-account OIDC issuer for external identity federation
- Provides lifecycle management scripts to start/stop instances to save costs

**Architecture:**
```
Internet → nginx (Static EIP) → K3s Server (private) ← K3s Agent
```

- **nginx Ingress:** Standalone node with your Elastic IP, proxies HTTP/HTTPS to K3s
- **K3s Server:** Control plane node running in the first public subnet
- **K3s Agent:** Worker node running in a second public subnet (or same subnet if only one available)
- **Security:** Intra-cluster communication allowed, optional SSH access from your IP
- **Secrets:** Cluster token and kubeconfig stored as SSM SecureString parameters
- **IAM:** EC2 instances have roles to read token from SSM, write kubeconfig, and write ArgoCD password

## Prerequisites

- **Terraform** >= 1.7.0
- **AWS CLI** configured with appropriate credentials
- **IAM user** with permissions to manage EC2, SSM, IAM, and S3 resources (used by Terraform via the `terraform-iac` profile)
- **Existing AWS Resources:**
  - VPC with internet connectivity
  - At least one public subnet (two recommended for HA)
  - Elastic IP allocation for nginx ingress (managed outside Terraform)
  - EC2 key pair for SSH access
  - S3 bucket for Terraform state backend

## Repository Structure

```
.
├── main.tf                    # Root module - data sources & k3s module invocation
├── variables.tf               # Input variables (VPC ID, subnets, instance types, etc.)
├── outputs.tf                 # Outputs (IPs, kubeconfig, resource IDs)
├── providers.tf               # AWS & Random provider configuration
├── backend.tf                 # S3 backend configuration (empty, use -backend-config)
├── terraform.tfvars           # Your actual values (gitignored)
├── terraform.tfvars.example   # Template for terraform.tfvars
├── backend.hcl                # Backend config values (gitignored)
├── backend.hcl.example        # Template for backend.hcl
├── aws-config                 # AWS CLI config for profile (gitignored)
├── aws-config.example         # Template for aws-config
├── aws-credentials            # AWS credentials file (gitignored)
├── aws-credentials.example    # Template for aws-credentials
├── docs/                      # Additional documentation
│   ├── adrs/                 # Architecture Decision Records
│   └── sops/                 # SOPS configuration
├── modules/
│   ├── k3s-cluster/          # K3s cluster module
│   │   ├── main.tf           # Security groups, IAM roles, EC2 instances
│   │   ├── variables.tf      # Module inputs
│   │   ├── outputs.tf        # Module outputs
│   │   ├── user_data/        # Cloud-init scripts (server.sh, agent.sh)
│   │   └── README.md         # Module documentation
│   └── nginx-ingress/        # nginx load balancer/ingress module
│       ├── main.tf           # Security groups, EC2 instance, EIP association
│       ├── variables.tf      # Module inputs
│       ├── outputs.tf        # Module outputs
│       ├── user_data/        # Cloud-init script (nginx.sh)
│       └── README.md         # Module documentation
└── scripts/
    ├── get-kubeconfig.sh     # Fetch kubeconfig from SSM
    ├── start-cluster.sh      # Start EC2 instances
    └── stop-cluster.sh       # Stop EC2 instances to save costs
```

## Initial Setup

### 1. Configure AWS Credentials

Copy example files and fill in your values:

```bash
cp aws-config.example aws-config
cp aws-credentials.example aws-credentials
```

Edit `aws-credentials` and add your AWS access keys for the `terraform-iac` profile:
```ini
[terraform-iac]
aws_access_key_id = YOUR_ACCESS_KEY_ID
aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
```

Edit `aws-config` if you need to change region (default is `us-east-1`).

### 2. Configure Terraform Backend

Copy the backend config template and fill in your S3 bucket details:

```bash
cp backend.hcl.example backend.hcl
```

Edit `backend.hcl` with your actual S3 bucket name and region:
```hcl
bucket  = "your-terraform-state-bucket"
key     = "state/terraform.tfstate"
region  = "us-east-1"
encrypt = true
```

Initialize Terraform with backend configuration:

```bash
terraform init -backend-config=backend.hcl
```

### 3. Configure Variables

Copy the variables template and provide your infrastructure IDs:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set:
- `vpc_id`: Your existing VPC ID
- `public_subnet_ids`: List of 2+ public subnet IDs (must have internet access)
- `key_name`: Your EC2 key pair name (optional, for SSH access)
- `ssh_allowed_cidrs`: Your IP address CIDR blocks for SSH access (e.g., `["1.2.3.4/32"]`)
- `nginx_eip_allocation_id`: Pre-existing Elastic IP allocation ID for the nginx ingress node
- `k3s_server_eip_allocation_id`: (Optional) Pre-existing Elastic IP for K3s server
- `ssm_token_name`: SSM parameter path for cluster token (e.g., `/k3s/cluster/token`)
- `ssm_kubeconfig_name`: SSM parameter path for kubeconfig (e.g., `/k3s/cluster/kubeconfig`)
- `ssm_argocd_password_name`: SSM parameter path for ArgoCD password (e.g., `/k3s/argocd/password`)
- Optional: Override instance types if needed (defaults: K3s `t4g.medium`, nginx `t4g.micro`)

### 4. Deploy Infrastructure

Review the plan:
```bash
terraform plan
```

Apply the configuration:
```bash
terraform apply
```

The deployment will:
1. Reference your existing Elastic IP for nginx ingress (static public IP)
2. Create security groups for K3s cluster and nginx ingress
3. Generate random cluster join token and store in SSM
4. Create IAM roles for EC2 instances to access SSM
5. Launch K3s server instance (installs K3s, ArgoCD, and uploads kubeconfig to SSM)
6. Launch K3s agent instance (joins the cluster using token from SSM)
7. **Launch nginx ingress instance** (installs nginx and associates the pre-existing Elastic IP)

**Note:** First boot takes ~2-3 minutes for K3s installation and cluster formation.

## Usage

### Initial Workspace Setup

After cloning this repository on a new machine:

1. **Configure AWS credentials:**
   Ensure you have the AWS access keys configured for the `terraform-iac` profile. These credentials must be obtained through a secure distribution method (1Password, secure file share, etc.). Place them in your `aws-credentials` file in the repository root:
   ```ini
   [terraform-iac]
   aws_access_key_id = YOUR_ACCESS_KEY_ID
   aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
   ```
   **Note:** The `aws-credentials` file is gitignored and must be set up manually on each machine.

2. **Set up AWS environment variables:**
   ```bash
   source ./scripts/init.sh
   ```
   This exports `AWS_PROFILE` and `AWS_REGION` so you don't need to specify them in every command.

3. **Ensure you have the SSH key:**
   The EC2 key pair private key (`chad-k3s.pem`) is not stored in AWS. You'll need to obtain it through your secure distribution method (1Password, secure file share, etc.) and place it at `~/chad-k3s.pem` with proper permissions:
   ```bash
   chmod 600 ~/chad-k3s.pem
   ```

4. **Initialize Terraform:**
   ```bash
   terraform init -backend-config=backend.hcl
   ```

### Helper Scripts

The `scripts/` directory contains convenient helper scripts:

| Script | Purpose |
|--------|---------|
| `init.sh` | Source this to set AWS environment variables (`source ./scripts/init.sh`) |
| `get-kubeconfig.sh` | Fetch kubeconfig from SSM and save locally |
| `get-argocd-password.sh` | Retrieve ArgoCD admin password |
| `healthcheck-infra.sh` | Run read-only checks for AWS, k3s, ArgoCD, nginx, and public OIDC endpoints |
| `start-cluster.sh` | Start all instances (K3s + nginx) |
| `stop-cluster.sh` | Stop all instances to save costs |
| `ssh-k3s-server.sh` | SSH into the K3s server node |
| `ssh-k3s-agent.sh` | SSH into the K3s agent node |
| `ssh-nginx.sh` | SSH into the nginx ingress node |

**Note:** Start/stop scripts manage all three instances (K3s server, K3s agent, and nginx).

Run the read-only infrastructure health check from the repository root:

```bash
./scripts/healthcheck-infra.sh
```

The script checks AWS instance state and status, Kubernetes API request serving
and readiness, node readiness, ArgoCD availability, public HTTPS routes, and
the OIDC discovery and JWKS endpoints. It exits with status `1` when any check
fails.

### Accessing the Cluster

Fetch the kubeconfig from SSM:

```bash
./scripts/get-kubeconfig.sh
export KUBECONFIG=$(pwd)/kubeconfig.yaml
```

The script runs in a child shell, so it cannot set `KUBECONFIG` in your current
shell automatically. Run the export shown above before invoking `kubectl`.

Or manually:
```bash
terraform output -raw kubeconfig > kubeconfig.yaml
export KUBECONFIG=$(pwd)/kubeconfig.yaml
```

Verify cluster access:
```bash
kubectl get nodes
```

### Cost Management: Start/Stop Cluster

**Stop instances when not in use** (you only pay for EBS storage when stopped):

```bash
./scripts/stop-cluster.sh
```

**Start instances when needed:**

```bash
./scripts/start-cluster.sh
```

**Note:** The scripts manage K3s nodes and the nginx ingress node. All three instances are stopped/started together.

The kubeconfig remains valid across restarts if using an Elastic IP. Otherwise, you'll need to regenerate it after restart if the server gets a new public IP.

### SSH Access

If you configured `key_name` and `ssh_allowed_cidrs`:

Convenience scripts are provided for quick SSH access (see [Helper Scripts](#helper-scripts)):
- `./scripts/ssh-k3s-server.sh` — SSH into the K3s server node
- `./scripts/ssh-k3s-agent.sh` — SSH into the K3s agent node
- `./scripts/ssh-nginx.sh` — SSH into the nginx ingress node

Or use manual commands:

```bash
# SSH to server
ssh ec2-user@$(terraform output -raw k3s_server_public_ip)

# SSH to agent
ssh ec2-user@$(terraform output -raw k3s_agent_public_ip)

# SSH to nginx
ssh ec2-user@$(terraform output -raw nginx_public_ip)
```

Check K3s logs:
```bash
sudo journalctl -u k3s -f        # On server
sudo journalctl -u k3s-agent -f  # On agent
```

### nginx Ingress

The nginx ingress node provides a dedicated load balancer with the static IP. TLS is terminated on nginx for `apis.rotorlabs.io`, `admin.rotorlabs.io`, and `apps.rotorlabs.io`.

TLS certificate generation, validation, SSM deployment, renewal, rollback, and troubleshooting are documented in the [rotorlabs SSL certificate SOP](docs/sops/ssl/rotorlabs/README.md). Use `scripts/rotate-nginx-tls.sh` for certificate deployment and rotation rather than replacing the Nginx instance.

**Access your cluster:**
```bash
# Your static IP now routes to K3s
curl http://$(terraform output -raw nginx_public_ip)
```

**SSH to nginx node:**
```bash
ssh ec2-user@$(terraform output -raw nginx_public_ip)
```

**View nginx configuration:**
```bash
# On nginx instance
sudo cat /etc/nginx/conf.d/k3s-proxy.conf
sudo nginx -t  # Test config
sudo systemctl reload nginx  # After changes
```

**Check nginx logs:**
```bash
sudo journalctl -u nginx -f
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

**Why use nginx ingress?**
- **Stable endpoint:** Your static IP doesn't change even if K3s nodes are recreated
- **Load balancing:** Distribute traffic across multiple K3s nodes (edit upstream config)
- **SSL termination:** Terminate TLS at the nginx layer using the rotorlabs certificate deployment SOP
- **Custom routing:** Advanced proxy rules, rate limiting, caching, etc.
- **Separation:** Keep ingress concerns separate from the cluster

**Default configuration:** The nginx instance is pre-configured with two upstreams:
- **K3s backend:** Proxies HTTP traffic on port 80 to the K3s server's private IP
- **ArgoCD proxy:** Routes `admin.rotorlabs.io/argocd` to the ArgoCD server via K3s NodePort 30080

You can customize the config for additional backends or advanced features.

### ArgoCD GitOps

ArgoCD is automatically installed on the K3s server during first boot for GitOps-based application deployment. It's accessible at **https://admin.rotorlabs.io/argocd** via the nginx reverse proxy.

**Access ArgoCD UI:**

```bash
# Ensure DNS points admin.rotorlabs.io to the nginx server's Elastic IP
# Get the admin password
./scripts/get-argocd-password.sh

# Open in browser
https://admin.rotorlabs.io/argocd
```
- Username: `admin`
- Password: Retrieved from script above

**Or access password via Terraform outputs:**
```bash
terraform output -raw argocd_admin_password
```

**What ArgoCD provides:**
- **GitOps workflow:** Declare your applications in Git, ArgoCD deploys them
- **Automated sync:** Keeps cluster state in sync with Git repository
- **Rollback capability:** Easy rollback to previous versions
- **Multi-environment:** Manage dev/staging/prod from one place

**Getting started with ArgoCD:**

1. **Install ArgoCD CLI** (optional but recommended):
   ```bash
   # macOS
   brew install argocd
   
   # Linux
   curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
   chmod +x /usr/local/bin/argocd
   ```

2. **Login via CLI:**
   ```bash
   # Via nginx (HTTP)
   argocd login admin.rotorlabs.io:443 --username admin --password $(terraform output -raw argocd_admin_password) --insecure --grpc-web
   ```

3. **Create your first application:**
   ```bash
   argocd app create my-app \
     --repo https://github.com/your-org/your-repo \
     --path k8s \
     --dest-server https://kubernetes.default.svc \
     --dest-namespace default
   ```

4. **Sync the application:**
   ```bash
   argocd app sync my-app
   ```

**Important:** This infrastructure repo installs ArgoCD as platform tooling. Your actual application manifests should live in separate Git repositories that ArgoCD references.

**Change the default password:**
```bash
argocd account update-password --current-password $(terraform output -raw argocd_admin_password)
```

## Key Features & Design Decisions

Architectural decisions are documented as ADRs in [`docs/adrs/`](docs/adrs/):

| ADR | Decision |
|-----|----------|
| [001](docs/adrs/001-ssm-parameter-store.md) | SSM Parameter Store for secrets management |
| [002](docs/adrs/002-arm-ec2-instances.md) | ARM (Graviton) EC2 instances for cost/performance |
| [003](docs/adrs/003-nginx-self-managed-ingress.md) | Self-managed nginx as ingress over managed load balancers |
| [004](docs/adrs/004-network-security-model.md) | Two-security-group network model |

### Implementation Details

**Instance Type Compatibility:** The code automatically filters subnets based on availability zone support for the selected instance type. ARM instances (`t4g.*`) may not be available in all AZs, so the deployment intelligently selects compatible subnets. Default is `t4g.medium` for K3s nodes.

**User Data Scripts:**
- **Server:** Installs K3s in server mode, fetches token from SSM, generates kubeconfig, replaces `127.0.0.1` with public IP, uploads to SSM. Also installs ArgoCD and stores the admin password in SSM.
- **Agent:** Installs K3s in agent mode, fetches token from SSM, connects to server's private IP
- **nginx:** Installs nginx, configures reverse proxy to K3s server and ArgoCD, ready for HTTP/HTTPS traffic

## Outputs

After successful `terraform apply`, you can access:

| Output | Description | Command |
|--------|-------------|---------|
| `nginx_eip` | nginx Elastic IP address (static) | `terraform output nginx_eip` |
| `nginx_public_ip` | nginx ingress public IP (same as EIP) | `terraform output nginx_public_ip` |
| `nginx_instance_id` | nginx EC2 instance ID | `terraform output nginx_instance_id` |
| `nginx_security_group_id` | nginx security group ID | `terraform output nginx_security_group_id` |
| `k3s_server_public_ip` | Server public IP | `terraform output k3s_server_public_ip` |
| `k3s_agent_public_ip` | Agent public IP | `terraform output k3s_agent_public_ip` |
| `k3s_server_instance_id` | Server EC2 instance ID | `terraform output k3s_server_instance_id` |
| `k3s_agent_instance_id` | Agent EC2 instance ID | `terraform output k3s_agent_instance_id` |
| `k3s_security_group_id` | K3s cluster security group ID | `terraform output k3s_security_group_id` |
| `kubeconfig` | Full kubeconfig content | `terraform output -raw kubeconfig > kubeconfig.yaml` |
| `kubeconfig_ssm_parameter_name` | SSM parameter name for kubeconfig | `terraform output kubeconfig_ssm_parameter_name` |
| `argocd_admin_password` | ArgoCD initial admin password | `terraform output -raw argocd_admin_password` |
| `argocd_server_url` | ArgoCD UI URL | `terraform output argocd_server_url` |
| `argocd_ssm_parameter_name` | SSM parameter name for ArgoCD password | `terraform output argocd_ssm_parameter_name` |
| `vpc_id` | Adopted VPC ID | `terraform output vpc_id` |
| `public_subnet_ids` | Adopted public subnet IDs | `terraform output public_subnet_ids` |
| `aws_region` | AWS region in use | `terraform output aws_region` |

## Troubleshooting

### Cluster not forming
1. Check server user data logs: `ssh` to server and `cat /var/log/cloud-init-output.log`
2. Verify SSM token was created: `aws ssm get-parameter --name /k3s/cluster/token --with-decryption`
3. Check K3s service: `sudo systemctl status k3s` (server) or `sudo systemctl status k3s-agent` (agent)

### Can't connect with kubectl
1. Ensure kubeconfig has server's public IP (not 127.0.0.1)
2. Verify security group allows traffic from your IP to port 6443
3. If server restarted without Elastic IP, the public IP changed - re-run server user data or get new kubeconfig

### nginx not routing traffic
1. Check nginx is running: `ssh` to nginx node and `sudo systemctl status nginx`
2. View nginx logs: `sudo tail -f /var/log/nginx/error.log`
3. Test backend connectivity: `curl http://<k3s-server-private-ip>` from nginx instance
4. Verify security groups allow nginx → K3s traffic
5. Check nginx config: `sudo nginx -t` and review `/etc/nginx/conf.d/k3s-proxy.conf`

### Instance type not available
If you get an error about instance type availability, either:
- Choose a different instance type (e.g., `t3.small` for x86_64)
- Select subnets in different availability zones
- Update the AMI filter in the module to match your instance architecture

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

This will:
- Terminate all EC2 instances (K3s server, agent, and nginx)
- Disassociate the pre-existing nginx Elastic IP (EIP itself remains)
- Delete security groups
- Delete IAM roles and instance profile
- Delete SSM parameters (token, kubeconfig, and ArgoCD password)

**Note:** Your VPC and subnets are **not** managed by this code and will remain.

## Philosophy & Design Principles

- **Cost-conscious:** Target < $50/month (t4g.medium for K3s, t4g.micro for nginx, stop when idle)
- **Single environment:** No multi-stage complexity, perfect for personal learning
- **Adopt, don't recreate:** Uses existing VPC/subnets via data sources, no new networking
- **Interruption acceptable:** Not production; downtime during experiments is fine
- **Learning-focused:** Heavily commented code, clear structure for future reference
- **Modular design:** Separate modules for K3s cluster and nginx ingress for flexibility

## Security & Secrets Management

**Token Strategy:**
- Cluster join token generated by Terraform (`random_password`) 
- Stored only in SSM SecureString (never in repo or user_data directly)
- EC2 instances fetch at boot via AWS CLI with IAM permissions
- Also stored in Terraform state (treat state bucket as sensitive)

**Rotating the token:**
```bash
terraform taint module.k3s.random_password.cluster_token
terraform apply
```
This generates a new token, updates SSM, and replaces instances.

**What's never committed:**
- `terraform.tfvars` (your actual IDs and values)
- `backend.hcl` (S3 bucket names)
- `aws-credentials` (access keys)
- `aws-config` (profile configuration)
- `kubeconfig.yaml` (cluster access)

All sensitive files are gitignored. State is stored remotely in encrypted S3.

## Future Enhancements

Potential additions you might consider:
- Multi-node agent scaling (ASG or count parameter)
- CloudWatch log shipping for K3s logs
- Application Load Balancer for ingress
- EBS volume attachments for persistent storage
- Route53 DNS records for stable cluster endpoint
- Terraform workspaces for multiple environments
- Spot instances for additional cost savings

## References

- [K3s Documentation](https://docs.k3s.io/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Systems Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)

---

*Learning-oriented infrastructure. Adjust iteratively based on your needs.*
