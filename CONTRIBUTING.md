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
- Run applicable validation before committing. For Terraform changes, run `terraform fmt`, `terraform validate`, and review the resulting plan when credentials and backend access are available.

## Pull Requests

- Use a semantic commit-style title and include the related issue reference.
- Explain what changed, why it changed, and how it was validated.
- Call out infrastructure replacements, security-group changes, secret-handling changes, and other operational impacts explicitly.
- Keep the pull request focused and ensure all required checks pass before merging.
