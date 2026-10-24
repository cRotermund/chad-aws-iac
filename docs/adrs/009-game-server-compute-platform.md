# ADR 009: Game Server Compute Platform

- **Status:** Proposed
- **Date:** 2026-10

## Context

The Satisfactory dedicated server currently runs on a manually created
`t2.xlarge` EC2 instance with Amazon Linux and a default security group. It is
stopped, and its data will be discarded during the rebuild. The replacement
must run a single x86_64 dedicated game server, be cost-effective, and stay
simple to operate. Game servers are a poor fit for K3s: they are stateful, a
single process, and not a good match for container orchestration.

## Decision

Run each game server as a **single EC2 instance** managed directly by Terraform
in the `game-servers` stack, rather than as a workload on the K3s cluster.

- **Instance type:** `m6a.xlarge` (4 vCPU, 16 GiB, AMD EPYC, x86_64,
  non-burstable). Satisfactory ships x86_64 binaries, so Graviton (ARM)
  instances are excluded without emulation.
- **Operating system:** Debian 13 (`debian-13-amd64`), selected with an
  `aws_ami` data source filtered by Debian's owner ID (`136693071363`) and name
  pattern, so the AMI resolves to the latest image rather than a hardcoded ID.
- **Storage:** Root EBS volume only. Game save data lives on the root volume.
  Data is recreated, not preserved, during the rebuild.
- **Metadata:** IMDSv2 required.
- **Access:** SSH key pair and `ssh_allowed_cidrs`, as in the homelab.
- **Public IP:** Terraform-owned EIP, per [ADR 007](007-game-server-network-isolation.md).

Multiple game servers would be declared as additional instances in the same
stack. An Auto Scaling group is not required for the current use case.

### Alternatives Considered

| Option | Pros | Cons |
|--------|------|------|
| Graviton (`m7g`/`t4g`) instances | Lower cost per vCPU | Not compatible with x86-only game binaries without emulation |

## Consequences

- **Positive:** Minimal moving parts; the game server's lifecycle is independent
  of the homelab cluster.
- **Positive:** `m6a.xlarge` is a non-burstable instance with consistent CPU
  performance, versus the burstable `t2.xlarge` it replaces.
- **Positive:** Using a data source for the AMI keeps the image current without
  manual updates.
- **Negative:** No automatic recovery beyond EC2 instance recovery; the server
  is a single point of failure.
- **Negative:** Debian 13 patching and game updates are manual or must be
  handled by provisioning scripts.
- **Negative:** Resolving the AMI at plan time means an OS image update can
  replace the instance on the next apply unless `ignore_changes` is set on the
  AMI attribute. This must be decided before the first apply.
</content>
