# AGENTS — OpenCode configuration

## Architecture Decision Records (ADRs)

This repo maintains ADRs in [`docs/adrs/`](docs/adrs/). These are the canonical record of significant design decisions and the rationale behind them.

### When proposing or implementing changes:

1. **Review existing ADRs** — Before making a change that touches infrastructure design, secrets management, networking, instance selection, or ingress, review the ADRs to ensure alignment with documented decisions. If your proposed approach contradicts an ADR, call it out explicitly.

2. **Propose a new ADR for major decisions** — If you're making a significant architectural choice, ask the user whether they want to create an ADR to document it. A "significant" decision is one that:
   - Changes how secrets/tokens are managed
   - Switches compute platforms (instance types, architectures, container orchestrators)
   - Alters the ingress/networking model
   - Introduces or removes an AWS service dependency
   - Changes the security posture

3. **ADR format** — Use the existing documents as a template. Each ADR should have:
   - **Status:** Accepted (or Proposed for new ones)
   - **Date:** YYYY-MM
   - **Context:** The problem being solved
   - **Decision:** What was chosen
   - **Alternatives Considered:** A table with pros/cons
   - **Consequences:** Both positive and negative outcomes