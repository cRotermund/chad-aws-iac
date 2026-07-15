# ADR 004: Network Security Model

- **Status:** Accepted
- **Date:** 2025-07

## Context

The cluster consists of three EC2 instances (K3s server, K3s agent, nginx ingress) in public subnets of an existing VPC. A security model must:

- Allow K3s cluster communication (server ↔ agent)
- Allow nginx to reach K3s NodePort services
- Permit external HTTP/HTTPS traffic to reach applications
- Support SSH access for operational troubleshooting
- Minimize unnecessary exposure

## Decision

Use a **two-security-group model** with targeted rules:

1. **K3s security group** (`k3s-cluster-sg`):
   - Self-referencing rule: all traffic between members of the SG (server ↔ agent ↔ all cluster pods)
   - Ingress from nginx SG: TCP 30000-32767 (K3s NodePort range) for service exposure
   - Ingress from operator CIDRs: TCP 22 (SSH)
   - Egress: all outbound (for package updates and image pulls)

2. **nginx security group** (`nginx-ingress-sg`):
   - Ingress from internet (0.0.0.0/0): TCP 80 (HTTP) and TCP 443 (HTTPS)
   - Ingress from operator CIDRs: TCP 22 (SSH)
   - Egress: all outbound

### Alternatives Considered

| Option | Pros | Cons |
|--------|------|------|
| **Two-SG model** (chosen) | Clear separation of concerns; nginx SG can be referenced by K3s SG for targeted NodePort access | Requires managing two SGs |
| Single SG for all nodes | Simpler to manage | No clean way to restrict K3s-specific ports from public access without mixing concerns |
| Private subnets + NAT Gateway | Defense in depth; instances not directly internet-accessible | NAT Gateway adds ~$32+/month; overkill for learning cluster |

## Consequences

- **Positive:** Security group self-reference ensures any future K3s node (e.g., additional agents) automatically gets intra-cluster access
- **Positive:** nginx ingress has a dedicated SG, making it easy to audit what's exposed to the internet
- **Positive:** NodePort traffic is explicitly allowed only from the nginx SG, not the open internet
- **Negative:** Instances are in public subnets — defense relies primarily on security groups rather than network topology
- **Negative:** All cluster nodes share the same K3s SG — fine-grained per-service rules would require additional SGs