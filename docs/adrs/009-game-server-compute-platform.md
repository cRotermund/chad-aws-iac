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
- **Operating system:** Debian 13 (`debian-13-amd64`), pinned to a specific AMI
  ID (`ami-0bd74f3706bb4acb8`, from Debian's owner ID `136693071363`). Upgrades
  are deliberate: a new AMI ID is set in Terraform and applied explicitly. The
  image is not looked up dynamically, so a routine Debian release cannot replace
  a running server.
- **Storage:** Root EBS volume only. Game save data lives on the root volume.
  Data is recreated, not preserved, during the rebuild.
- **Metadata:** IMDSv2 required.
- **Access:** SSH key pair and `ssh_allowed_cidrs`, as in the homelab.
- **Public IP:** Externally managed EIP bound by Terraform, per [ADR 007](007-game-server-network-isolation.md).

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
- **Positive:** Pinning the AMI keeps routine image releases from replacing a
  running server. Upgrades are an explicit, reviewable change.
- **Negative:** No automatic recovery beyond EC2 instance recovery; the server
  is a single point of failure.
- **Negative:** Debian 13 patching and game updates are manual or must be
  handled by provisioning scripts.
- **Negative:** Moving to a newer AMI is a manual step. Setting a new AMI ID in
  Terraform replaces the instance, so the root volume and any save data on it
  are lost unless backed up first.
</content>
