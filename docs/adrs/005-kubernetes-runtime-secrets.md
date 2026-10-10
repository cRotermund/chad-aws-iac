# ADR 005: Manage Kubernetes Runtime Secrets Through External Secrets

- **Status:** Accepted
- **Date:** 2026-10

## Context

The cluster has two different secret-management needs:

- Infrastructure and bootstrap components need secrets while Terraform and EC2
  user data are provisioning the cluster. Examples include the K3s join token,
  kubeconfig, Argo CD bootstrap password, and TLS material used by nginx.
- Kubernetes workloads need selected application secrets during normal runtime.
  Those secrets must not be committed to Git, copied into Terraform variables,
  or exposed through broad EC2 instance permissions.

ADR 001 established AWS Systems Manager Parameter Store as the infrastructure
secret store. The OIDC federation work adds a safe identity mechanism for
Kubernetes service accounts to obtain short-lived AWS credentials without
static AWS keys. The two mechanisms should have clearly separated ownership and
access boundaries.

## Decision

Continue using AWS Systems Manager Parameter Store with `SecureString` values
for infrastructure and bootstrap secrets managed by the IaC repository. This
includes secrets consumed by Terraform, EC2 instance profiles, and documented
operator workflows.

Manage Kubernetes application runtime secrets with External Secrets Operator
(ESO), delivered through the GitOps repository. ESO will read approved values
from SSM and materialize them as Kubernetes `Secret` objects in the consuming
namespace.

The runtime integration will use:

- The stable K3s OIDC issuer at `https://apis.rotorlabs.io/aws-oidc`.
- Short-lived service-account web-identity tokens exchanged through AWS STS.
- A dedicated ESO authentication IAM role trusted by the Kubernetes OIDC
  provider.
- A separate SSM read role with narrowly scoped access to an approved
  parameter path.
- A restricted `ClusterSecretStore` and explicit namespace/resource policy in
  the GitOps repository.
- Argo CD as the delivery mechanism for ESO and its Kubernetes resources.

Applications will not receive long-lived AWS access keys or direct access to
the AWS secret store. IAM policies must grant only the required SSM actions and
parameter resources. The initial approved SSM path is
`/kubernetes/appsecrets/`; new namespaces or parameter paths require an
explicit reviewed change in the owning repository.

The IaC repository owns the OIDC issuer prerequisites, public discovery and
JWKS routes, AWS IAM provider, IAM roles, and IAM policies. The GitOps
repository owns the ESO installation, Kubernetes service account, RBAC,
`ClusterSecretStore`, and `ExternalSecret` resources. Neither repository should
manage the same resource.

## Alternatives Considered

| Option | Pros | Cons |
|--------|------|------|
| **ESO backed by SSM and K3s OIDC** (chosen) | No credentials in Git or pods; short-lived AWS identity; declarative delivery; reuses existing SSM and OIDC work | Requires ESO, IAM trust configuration, and cross-repository coordination |
| Store Kubernetes `Secret` manifests in Git | Simple Argo CD workflow; no external controller | Secret values remain in Git history unless an additional encryption workflow is added; rotation is manual |
| Use SOPS-encrypted Kubernetes manifests | Keeps encrypted values in Git; works without a runtime operator | Key distribution and decryption permissions become another bootstrap concern; rotation and access boundaries are less centralized |
| Give workloads or nodes direct SSM permissions | Fewer components; simple initial implementation | Broadens AWS access; makes namespace and workload isolation difficult; encourages static or shared credentials |
| AWS Secrets Manager | Native secret rotation integrations and richer secret lifecycle features | Additional cost and service complexity for the current platform; does not remove the need for workload identity and ESO |
| HashiCorp Vault | Platform-independent secret engines and advanced workflows | Requires operating another highly available security-critical platform service |

## Consequences

- **Positive:** Secret values and AWS credentials remain outside both Git
  repositories.
- **Positive:** Kubernetes workloads receive ordinary Kubernetes Secrets while
  AWS access is limited to the ESO control-plane integration.
- **Positive:** Short-lived OIDC credentials avoid distributing long-lived AWS
  keys to nodes or applications.
- **Positive:** Infrastructure bootstrap and application runtime secret
  lifecycles have separate IAM and repository ownership boundaries.
- **Negative:** ESO becomes a platform dependency for creating or refreshing
  application Secrets.
- **Negative:** The OIDC issuer, public JWKS route, IAM roles, SSM paths, ESO,
  and Argo CD form a cross-system recovery chain.
- **Negative:** Existing Kubernetes Secrets remain available during an ESO
  outage, but new values and refreshes may be delayed until ESO recovers.
- **Negative:** Terraform state and SSM access still require protection because
  infrastructure operators may be able to retrieve bootstrap secrets.

## Operational Requirements

- Keep the OIDC issuer URL immutable after adoption; changing it is an
  identity migration requiring coordinated changes in both repositories.
- Define and document approved SSM parameter paths before enabling ESO.
- Validate both successful synchronization and denied access for an unapproved
  parameter and namespace.
- Rotate application secret values in SSM, then verify ESO refreshes the
  resulting Kubernetes Secret without committing the value to Git.
- Document recovery for loss of public OIDC discovery/JWKS availability, IAM
  trust failures, ESO outages, and stale Kubernetes Secrets in the GitOps
  repository's integration SOP.
