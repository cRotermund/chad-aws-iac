# ADR 008: Separate Terraform Stacks for Homelab and Game Servers

- **Status:** Proposed
- **Date:** 2026-10

## Context

The repository currently defines a single Terraform root at the top level,
covering the homelab K3s cluster and nginx ingress. Game server infrastructure
is about to be added. Game server resources change much more frequently than
the homelab, and a single state file would make every plan and apply evaluate
both sets of resources, increasing lock contention and blast radius.

## Decision

Maintain **one Terraform root per domain**, each with its own state file in the
same S3 backend bucket:

- `homelab/`: state key `homelab/terraform.tfstate`. Contains the existing
  K3s and nginx modules, moved from the repository root without changing the
  state key.
- `game-servers/`: state key `game-servers/terraform.tfstate`. Contains the
  game server VPC, security group, instance, and EIP association.

Shared, non-state resources (AWS credential files, `docs/`, and `scripts/`
where generic) remain at the repository root. Domain-specific scripts and
modules move with their root.

Each root uses its own `backend.hcl` (gitignored) pointing at the same bucket
with a different key. Plans, applies, and destroys run per root.

Moving the homelab does not change its state because state is addressed by
backend key, not file path. A `terraform plan` before and after the move must
show no changes.

## Consequences

- **Positive:** Game server changes cannot cause drift or failed plans in the
  homelab state, and vice versa.
- **Positive:** Each stack can be destroyed and rebuilt independently.
- **Positive:** Plans are faster and reviewed in the context of one domain.
- **Negative:** Shared values (for example region or tags) must be kept in
  sync manually across roots.
- **Negative:** Cross-stack references require explicit outputs or remote state
  data sources if ever needed.
- **Negative:** Existing local `.terraform/` directories and lock files must be
  regenerated when the homelab moves.
</content>
