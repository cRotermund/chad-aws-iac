# Contributing

## Issues

Create or identify a GitHub issue before making a non-trivial change. Every
commit that changes the repository should reference at least one issue using
one of these forms:

- `Refs #123` when the commit contributes to an issue without completing it.
- `Fixes #123` when the commit resolves the issue and should close it when merged.
- `Closes #123` when the commit resolves the issue and should close it when merged.

Use the issue reference in the commit body or footer. Keep unrelated issues in
separate commits.

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/) with an
imperative summary:

```text
<type>(<scope>): <imperative summary>

<optional explanation>

Refs #123
```

The scope is optional but recommended. Keep the summary concise, use lowercase
for the type and scope, and do not end the summary with a period.

### Commit Types

Use these standard types:

| Type | Use for |
|------|---------|
| `feat` | A new capability or user-visible feature |
| `fix` | A bug fix or behavior correction |
| `docs` | Documentation-only changes |
| `style` | Formatting or whitespace changes with no behavior change |
| `refactor` | Internal code restructuring with no behavior change |
| `perf` | A performance improvement |
| `test` | Adding or updating tests |
| `build` | Build system or dependency changes |
| `ci` | Continuous integration or automation changes |
| `chore` | Maintenance that does not fit another type |
| `revert` | Reverting an earlier commit |

Use scopes that describe the affected area, such as `k3s`, `networking`,
`terraform`, `scripts`, `docs`, or `adrs`.

Examples:

```text
fix(k3s): add public address to API certificate SANs

Refs #42
```

```text
feat(networking): allow operator access to the Kubernetes API

Fixes #57
```

```text
docs(contributing): document commit and issue conventions

Refs #61
```

For breaking changes, add `!` after the type or scope and explain the impact
in the body or a `BREAKING CHANGE:` footer:

```text
feat(terraform)!: replace the existing cluster networking model

BREAKING CHANGE: existing security groups must be migrated before apply.
Refs #100
```

## Change Hygiene

- Keep commits atomic and limited to one logical change.
- Do not commit credentials, private keys, kubeconfigs, Terraform state, or other secrets.
- Review `git diff` before committing and confirm that generated or local files are not included.
- Update relevant README documentation, module documentation, or ADRs when behavior or infrastructure decisions change.
- Run applicable validation before committing. For any Terraform change, run `terraform fmt -recursive` from the repository root, then confirm it is clean with `terraform fmt -check -recursive`.
- Run `terraform validate` after formatting, and review the resulting plan when credentials and backend access are available.

## Formatting

Terraform source is formatted with the canonical Terraform formatter. The entire
repository tree must be formatted rather than only the files changed in a
commit, because modules and root configuration are validated together.

Run from the repository root:

```bash
terraform fmt -recursive
terraform fmt -check -recursive
```

Formatting is required before validation, planning, review, and commit. Do not
manually reformat Terraform files in a way that causes `terraform fmt -check
-recursive` to fail.

## Version Pinning

Prefer pinning versioned resources wherever the tool supports it. Avoid floating
versions, where a value silently changes between runs, unless there is a
documented reason.

- **Terraform:** Pin `required_version` to an exact version. Do not use `>=`
  or `~>` ranges.
- **Providers:** Pin provider versions exactly, and commit the generated
  `.terraform.lock.hcl`.
- **Module sources:** Pin any remote module to a tag, commit, or exact version.
  Local modules are versioned with the repository.
- **Images and AMIs:** Pin AMI IDs and container images to an explicit ID, tag,
  or digest. Do not look up `most_recent` images in Terraform.
- **Software on hosts:** Pin package and binary versions in user data and
  scripts where the installer supports it (for example, the K3s version).
- **Charts, actions, and tooling:** Pin Helm charts, GitHub Actions, and CLI
  tools to exact versions or commit SHAs.

Upgrades are deliberate changes. Make a version bump in its own commit, reference
the issue, and review the `terraform plan` output before applying. Do not
combine a version bump with an unrelated change.

## Pull Requests

- Use a semantic commit-style title and include the related issue reference.
- Explain what changed, why it changed, and how it was validated.
- Call out infrastructure replacements, security-group changes, secret-handling changes, and other operational impacts explicitly.
- Keep the pull request focused and ensure all required checks pass before merging.
