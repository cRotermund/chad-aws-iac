# ADR 003: Allow Restricted External Kubernetes API Access

- **Status:** Accepted
- **Date:** 2026-09

## Context

Operators need to run `kubectl` from an approved workstation against the K3s
API server. The Kubernetes API listens on TCP port `6443`, but the cluster
security group intentionally does not expose arbitrary inbound traffic.

Without an explicit ingress rule, a correctly configured kubeconfig cannot
reach the API server from the operator workstation. The access mechanism must
support normal `kubectl` workflows without broadly exposing the control plane.

## Decision

Allow inbound TCP port `6443` on the K3s security group only from the CIDRs in
`kubectl_allowed_cidrs`. Operators should provide their workstation's public IP
as a `/32` CIDR when possible.

The rule is optional and remains disabled when `kubectl_allowed_cidrs` is empty.
Access to `6443` must not be opened to `0.0.0.0/0`.

## Alternatives Considered

| Option | Pros | Cons |
|--------|------|------|
| **Restricted TCP 6443 ingress** (chosen) | Works with standard kubectl; simple to operate; limits access to configured CIDRs | Requires updating Terraform when workstation IPs change; exposes the API endpoint to the internet at restricted source addresses |
| SSH tunnel through the K3s server | Does not expose the Kubernetes API publicly; uses existing SSH access | Requires an active tunnel and extra kubeconfig setup; less convenient for routine kubectl use |
| VPN or private network connectivity | Keeps the API private; scales better for multiple operators | Adds infrastructure, cost, and operational complexity |
| Public TCP 6443 from `0.0.0.0/0` | Simple configuration; works from any network | Unnecessarily exposes the control plane and increases attack surface; rejected |

## Consequences

- **Positive:** Operators can use standard `kubectl` commands from approved workstations.
- **Positive:** The API remains inaccessible from unapproved source addresses when CIDRs are narrowly configured.
- **Positive:** Access is managed declaratively through Terraform and is visible in the security group configuration.
- **Negative:** Workstation public IP changes require updating `kubectl_allowed_cidrs` and applying Terraform.
- **Negative:** The Kubernetes API remains internet-reachable at the network layer, even though source access is restricted.
- **Negative:** Operators must keep the API certificate SAN and kubeconfig endpoint aligned with the server's externally reachable address.
