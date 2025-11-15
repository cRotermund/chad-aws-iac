# k3s-cluster Module (Placeholder)

Goal: Provision a lightweight two-node k3s cluster (1 server, 1 agent) in existing subnets.

Planned Resources:
- (Implemented Phase 3) Security group allowing: SSH (optional), all intra-node traffic, outbound internet.
- (Future) EC2 server instance (`server_instance_type`).
- (Future) EC2 agent instance (`agent_instance_type`).
- (Future) Optional Elastic IP association (import existing allocation if provided).
- (Future) User data scripts to bootstrap k3s.

Inputs (see variables.tf):
- `vpc_id`, `subnet_ids`, instance types, token, optional EIP allocation id, tags.
- `ssh_allowed_cidrs` list for SSH ingress (leave empty to disable).

Outputs:
- `security_group_id` (current)
- (Future) Server public IP, Agent public IP, cluster API endpoint.

## Server vs Agent Behavior
The k3s server node runs the full control plane and provides the kubeconfig at:
`/etc/rancher/k3s/k3s.yaml` (owner root). The server systemd unit name is `k3s`.

The k3s agent node only runs the agent process; it does NOT include a local API server nor bundled kubeconfig. Its systemd unit name is `k3s-agent`.

Therefore:
- Running `kubectl` on the agent will fail unless you copy the server's kubeconfig or install your own.
- To view agent logs: `sudo journalctl -u k3s-agent -f`
- To view server logs: `sudo journalctl -u k3s -f`

### Accessing kubectl on the agent (optional)
Copy kubeconfig from server (adjust IP and key path):
```bash
scp -i ~/chad-k3s.pem ec2-user@<server_public_ip>:/etc/rancher/k3s/k3s.yaml ~/k3s.yaml
chmod 600 ~/k3s.yaml
export KUBECONFIG=~/k3s.yaml
kubectl get nodes
```

Or change the module to install a second server instead of an agent (not recommended for this minimal setup unless you want HA semantics).

Security & Secrets:
- `cluster_token` should reside only in a local `terraform.tfvars` (never committed).
- Long term: migrate token to AWS SSM Parameter + instance profile with read access.

Phases:
1. Skeleton (current)
2. Basic instances + SG
3. Bootstrap with static token variable
4. Token via SSM Parameter (optional)
5. Hardening (restrict SSH, enable automatic updates if desired)
