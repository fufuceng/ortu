# Recommended GitHub repository settings

Files in the repository provide checks, but GitHub settings decide whether they are enforced. Apply these settings after the first successful workflow run.

## General

- Default branch: `main`.
- Enable squash merge and automatically delete head branches.
- Disable force pushes and branch deletion on `main`.
- Enable private vulnerability reporting, Dependabot alerts, secret scanning, and push protection where GitHub offers them.

## Main branch ruleset

- Require a pull request before merging.
- Require at least one approving review.
- Dismiss stale approvals when new commits are pushed.
- Require all conversations to be resolved.
- Require branches to be up to date or use the merge queue.
- Require these status checks:
  - `Lint, test, coverage, package`
  - `Intel build and test`
  - `Analyze Swift`
  - `Review dependency changes`
- Block direct pushes and force pushes, including for administrators except during documented recovery.

Signed commits are useful but may raise the barrier for occasional contributors. Prefer signed release tags as a hard requirement; enable mandatory signed commits only if maintainers can support contributors who need setup help.

## Actions

- Allow GitHub-authored actions and explicitly approved third-party actions only.
- Default workflow token permissions to read-only.
- Require approval for workflows from first-time external contributors.
- Keep Dependabot enabled for GitHub Actions updates.

## Releases

- Protect version tags matching `v*` from update and deletion.
- Use an environment named `release` for signing/notarization secrets and require maintainer approval.
- Never expose certificate, notary, or Homebrew tap credentials to pull-request workflows.

