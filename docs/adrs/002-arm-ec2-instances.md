# ADR 002: Use ARM (Graviton) EC2 Instances

- **Status:** Accepted
- **Date:** 2025-07

## Context

The K3s cluster nodes and nginx ingress node need a compute platform. The primary requirements are:

- Lightweight enough for a personal/learning cluster (low cost)
- Sufficient performance for K3s control plane and basic workloads
- Compatible with K3s and standard Linux tooling (curl, dnf, kubectl, etc.)

## Decision

Use **ARM-based instances** (`t4g.medium` for K3s, `t4g.micro` for nginx) running Amazon Linux 2023 ARM AMIs.

### Alternatives Considered

| Option | Pros | Cons |
|--------|------|------|
| **ARM t4g** (chosen) | 20% cheaper than x86 equivalents; good price/performance; K3s has first-class ARM support | Not available in all AZs; requires AZ filtering logic |
| x86 t3 | Universally available; no compatibility concerns | Higher cost for equivalent performance |
| Spot instances | Even cheaper | Interruption risk adds complexity for a single-node control plane |

## Consequences

- **Positive:** Lower cost (~$30-35/month for 3 nodes running 24/7 vs ~$40-50 for x86 equivalents)
- **Positive:** AWS Graviton2 processors provide good performance for container workloads
- **Negative:** ARM instances may not be available in every AZ in a region; the deployment includes AZ filtering logic (`aws_ec2_instance_type_offerings`) to select compatible subnets
- **Negative:** Container images must support `linux/arm64`; most modern images do, but some niche images may not