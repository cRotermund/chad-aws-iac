# ADR 010: Per-Application Terraform Stacks

- **Status:** Proposed
- **Date:** 2026-11

## Context

Applications deployed on the homelab (starting with the Paprika recipe MCP
server) need small amounts of AWS infrastructure, such as an S3 bucket and an
IAM role. These applications are decoupled from the homelab itself and from the
game servers, and should not share state, lifecycle, or blast radius with
either.

## Decision

Add a top-level `apps/` directory containing **one Terraform root per
application**, e.g. `apps/paprika-mcp/`. Each stack has its own state key
(`apps/<name>/terraform.tfstate`) in the shared S3 backend bucket and its own
`backend.hcl`.

Workloads running in the k3s cluster authenticate with
`sts:AssumeRoleWithWebIdentity` against the cluster's service-account OIDC
issuer. The IAM OIDC provider remains owned by `homelab/`; app stacks look it
up with a data source by issuer URL and scope each role's trust policy to a
single namespace and service account.

## Alternatives Considered

| Option | Pros | Cons |
|--------|------|------|
| One stack per app under `apps/` (chosen) | Isolated state and blast radius; apps can be destroyed independently | Some boilerplate repeated per app |
| Single shared `apps/` stack | Less boilerplate | Apps share state and plans; one app's change can block others |
| Add resources to `homelab/` | No new stack | Mixes application assets with infrastructure |
| Long-lived IAM user keys | Works outside the cluster | Static credentials to store and rotate |

## Consequences

- **Positive:** App changes cannot cause drift or failed plans in other stacks.
- **Positive:** No static AWS credentials; roles are tied to a service account.
- **Negative:** Boilerplate (backend, providers, tags) is repeated per app until
  a shared module is justified.
- **Negative:** App stacks depend on the homelab's OIDC provider existing and
  its issuer URL staying stable.
