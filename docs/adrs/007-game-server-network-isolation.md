# ADR 007: Game Server Network Isolation

- **Status:** Proposed
- **Date:** 2026-10

## Context

Game server infrastructure currently runs in the account's default VPC
(`172.31.0.0/16`), the same network as the homelab K3s cluster and nginx
ingress. A misconfigured security group, route, or instance on either side can
affect the other, and the two workloads have different lifecycles: game servers
are rebuilt and reconfigured often, while the homelab changes rarely.

The account is a personal account, so the solution must avoid additional
billing or account-management overhead.

## Decision

Place game servers in a **dedicated VPC in the same AWS account and region**
(`us-east-1`), with no peering or Transit Gateway to the homelab VPC.

- **Network:** New VPC with public subnet(s) and an internet gateway. No NAT
  Gateway, which avoids a fixed hourly cost.
- **Ingress:** A dedicated security group opens only the game's required ports
  (TCP/UDP) to the internet, and SSH only from `ssh_allowed_cidrs`.
- **Public IP:** The game server's Elastic IP is created and released outside
  Terraform, matching the homelab pattern in [ADR 004](004-network-security-model.md).
  The `game-servers` stack looks it up with a `data "aws_eip"` block by
  allocation ID and binds it to the instance with `aws_eip_association`. Destroying
  the stack removes only the association; the address stays allocated and the
  public IP (`54.84.19.91`) is preserved. The stack does not track the EIP in
  state, so it cannot release it.
- **Cost tracking:** Resources are tagged through provider `default_tags`
  (`Project = "game-servers"`), and the tag is activated as a cost allocation
  tag in the Billing console.

Implementation is defined by [ADR 008](008-game-server-stack-separation.md) and
[ADR 009](009-game-server-compute-platform.md).

## Consequences

- **Positive:** Homelab and game server networks cannot reach each other unless
  a future decision adds connectivity.
- **Positive:** The game server can be destroyed and rebuilt without touching
  the homelab network.
- **Positive:** Costs remain on one bill and are separable through tags.
- **Negative:** The game server's public IP is a standing cost while it is
  associated or allocated, even when the instance is stopped.
- **Negative:** Game server ports are exposed directly to the internet; their
  security depends on the game's own authentication and the security group
  rules.
- **Negative:** A second VPC adds baseline AWS networking resources to manage.
</content>
