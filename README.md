
## Automation scripts

This repository includes helper scripts and a GitHub Actions workflow to apply branch protection and optionally create a release.

Files added

- .github/scripts/repo-protect-dryrun.sh — Dry-run script that prints the branch protection and release JSON payloads (safe; does not modify the repo).
- .github/scripts/repo-protect-and-release.sh — Script that applies branch protection and creates a release. Uses the GitHub REST API; requires a Personal Access Token (PAT) with repo scope.
- .github/workflows/apply-protection.yml — A manual workflow (workflow_dispatch) that runs the non-dry-run script. It expects a repository secret named PROTECTION_TOKEN containing a PAT with repo scope.

How to run (local)

1) Dry-run (recommended first):

```bash
# Optional: export a token to let the script inspect Actions runs
export GITHUB_TOKEN="ghp_xxx"
chmod +x .github/scripts/repo-protect-dryrun.sh
.github/scripts/repo-protect-dryrun.sh
```

2) Apply protection & create release (local)

```bash
export GITHUB_TOKEN="ghp_xxx"   # PAT with repo scope
chmod +x .github/scripts/repo-protect-and-release.sh
.github/scripts/repo-protect-and-release.sh
```

How to run via GitHub Actions (recommended)

1) Create a repository secret named PROTECTION_TOKEN containing a PAT with repo scope:
   - Repo → Settings → Secrets and variables → Actions → New repository secret
   - Name: PROTECTION_TOKEN
   - Value: ghp_xxx

2) Trigger the workflow manually:
   - Actions → Apply branch protection & create release → Run workflow

Environment variables and customization

- REQUIRED_APPROVALS: number of required approving reviews (default 1)
- ENFORCE_ADMINS: true/false (default true)
- REQUIRE_LINEAR_HISTORY: true/false (default false)
- REQUIRE_CONVERSATION_RESOLUTION: true/false (default false)
- CREATE_RELEASE: true/false (default true)
- RELEASE_TAG: the release tag to create (default v0.1.0)
- RELEASE_DRAFT: true/false (default true)

Notes and security

- Do not paste your PAT into public places or chat. Use repository secrets or run scripts locally.
- The workflow uses the PROTECTION_TOKEN secret because the Actions-provided GITHUB_TOKEN may not have permission to modify branch protection in some organizations.
- If you prefer, you can run the scripts locally instead of using the Action.
