# Architecture Decision Records

Significant design decisions for this repository, with context, alternatives,
and consequences. Each ADR uses the template: Status, Date, Context, Decision,
Alternatives Considered, and Consequences.

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [001](001-ssm-parameter-store.md) | Use SSM Parameter Store for Infrastructure Secrets | Accepted | 2025-07 |
| [002](002-arm-ec2-instances.md) | Use ARM (Graviton) EC2 Instances | Accepted | 2025-07 |
| [003](003-nginx-self-managed-ingress.md) | Self-Managed nginx as Ingress | Accepted | 2025-07 |
| [004](004-network-security-model.md) | Network Security Model | Accepted | 2025-07 |
| [005](005-kubernetes-runtime-secrets.md) | Manage Kubernetes Runtime Secrets Through External Secrets | Accepted | 2026-10 |
| [006](006-kubernetes-api-ingress.md) | Allow Restricted External Kubernetes API Access | Accepted | 2026-09 |
| [007](007-game-server-network-isolation.md) | Game Server Network Isolation | Proposed | 2026-10 |
| [008](008-game-server-stack-separation.md) | Separate Terraform Stacks for Homelab and Game Servers | Proposed | 2026-10 |
| [009](009-game-server-compute-platform.md) | Game Server Compute Platform | Proposed | 2026-10 |

## Adding an ADR

1. Use the next free number and a short kebab-case slug, e.g. `010-my-decision.md`.
2. Start with **Status: Proposed**. Change it to **Accepted** once the decision is implemented.
3. Add a row to the table above and to the table in the top-level `README.md`.
