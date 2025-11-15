# AWS Infrastructure as Code - K3s Cluster

This repository manages a lightweight **K3s Kubernetes cluster** running on AWS EC2 instances using Terraform. The infrastructure adopts existing VPC/networking resources and provisions a two-node K3s cluster (one server, one agent) with automated configuration via SSM Parameter Store.

## Overview

**What this does:**
- Provisions a 2-node K3s cluster (1 server + 1 agent) on ARM-based EC2 instances (`t4g.small` by default)
- Uses existing VPC and public subnets (no new network infrastructure created)
- Stores K3s cluster join token and kubeconfig securely in AWS SSM Parameter Store
- Optionally associates an existing Elastic IP with the server node
- Provides lifecycle management scripts to start/stop instances to save costs

**Architecture:**
- **K3s Server:** Control plane node running in the first public subnet
- **K3s Agent:** Worker node running in a second public subnet (or same subnet if only one available)
- **Security:** Intra-cluster communication allowed, optional SSH access from your IP
- **Secrets:** Cluster token and kubeconfig stored as SSM SecureString parameters
- **IAM:** EC2 instances have roles to read token from SSM and write kubeconfig back

## Prerequisites

- **Terraform** >= 1.7.0
- **AWS CLI** configured with appropriate credentials
- **Existing AWS Resources:**
  - VPC with internet connectivity
  - At least one public subnet (two recommended for HA)
  - Optional: EC2 key pair for SSH access
  - Optional: Elastic IP allocation for stable server IP
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
├── modules/
│   └── k3s-cluster/          # K3s cluster module
│       ├── main.tf           # Security groups, IAM roles, EC2 instances
│       ├── variables.tf      # Module inputs
│       ├── outputs.tf        # Module outputs
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
- `ssm_token_name`: SSM parameter path for cluster token (e.g., `/k3s/cluster/token`)
- `ssm_kubeconfig_name`: SSM parameter path for kubeconfig (e.g., `/k3s/cluster/kubeconfig`)
- Optional: Override instance types if needed (default: `t4g.small`)

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
1. Create security group for K3s cluster
2. Generate random cluster join token and store in SSM
3. Create IAM roles for EC2 instances to access SSM
4. Launch K3s server instance (installs K3s and uploads kubeconfig to SSM)
5. Launch K3s agent instance (joins the cluster using token from SSM)
6. Optionally associate your Elastic IP to the server

**Note:** First boot takes ~2-3 minutes for K3s installation and cluster formation.

## Usage

### Accessing the Cluster

Fetch the kubeconfig from SSM:

```bash
./scripts/get-kubeconfig.sh
```

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

The kubeconfig remains valid across restarts if using an Elastic IP. Otherwise, you'll need to regenerate it after restart if the server gets a new public IP.

### SSH Access

If you configured `key_name` and `ssh_allowed_cidrs`:

```bash
# SSH to server
ssh ec2-user@$(terraform output -raw k3s_server_public_ip)

# SSH to agent
ssh ec2-user@$(terraform output -raw k3s_agent_public_ip)
```

Check K3s logs:
```bash
sudo journalctl -u k3s -f        # On server
sudo journalctl -u k3s-agent -f  # On agent
```

## Key Features & Design Decisions

### Why SSM Parameter Store?
- **Security:** Cluster token and kubeconfig are encrypted at rest
- **No bootstrapping complexity:** Instances can self-configure by reading SSM on boot
- **Terraform integration:** Kubeconfig is available as a Terraform output immediately after apply

### Instance Type Compatibility
The code automatically filters subnets based on availability zone support for the selected instance type. ARM instances (`t4g.*`) may not be available in all AZs, so the deployment intelligently selects compatible subnets.

### User Data Scripts
- **Server:** Installs K3s in server mode, fetches token from SSM, generates kubeconfig, replaces `127.0.0.1` with public IP, and uploads to SSM
- **Agent:** Installs K3s in agent mode, fetches token from SSM, connects to server's private IP

### Network Security
- Instances within the cluster can communicate freely (security group self-reference)
- SSH access is optional and restricted to your specified CIDR blocks
- All outbound traffic allowed (for package updates and container image pulls)

## Outputs

After successful `terraform apply`, you can access:

| Output | Description | Command |
|--------|-------------|---------|
| `k3s_server_public_ip` | Server public IP | `terraform output k3s_server_public_ip` |
| `k3s_agent_public_ip` | Agent public IP | `terraform output k3s_agent_public_ip` |
| `kubeconfig` | Full kubeconfig content | `terraform output -raw kubeconfig > kubeconfig.yaml` |
| `k3s_server_instance_id` | Server EC2 instance ID | `terraform output k3s_server_instance_id` |
| `k3s_agent_instance_id` | Agent EC2 instance ID | `terraform output k3s_agent_instance_id` |

## Troubleshooting

### Cluster not forming
1. Check server user data logs: `ssh` to server and `cat /var/log/cloud-init-output.log`
2. Verify SSM token was created: `aws ssm get-parameter --name /k3s/cluster/token --with-decryption`
3. Check K3s service: `sudo systemctl status k3s` (server) or `sudo systemctl status k3s-agent` (agent)

### Can't connect with kubectl
1. Ensure kubeconfig has server's public IP (not 127.0.0.1)
2. Verify security group allows traffic from your IP to port 6443
3. If server restarted without Elastic IP, the public IP changed - re-run server user data or get new kubeconfig

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
- Terminate both EC2 instances
- Delete security group
- Delete IAM roles and instance profile
- Delete SSM parameters (token and kubeconfig)

**Note:** Your VPC, subnets, and Elastic IP (if used) are **not** managed by this code and will remain.

## Philosophy & Design Principles

- **Cost-conscious:** Target < $50/month (use t4g.small, stop when idle)
- **Single environment:** No multi-stage complexity, perfect for personal learning
- **Adopt, don't recreate:** Uses existing VPC/subnets via data sources, no new networking
- **Interruption acceptable:** Not production; downtime during experiments is fine
- **Learning-focused:** Heavily commented code, clear structure for future reference

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
