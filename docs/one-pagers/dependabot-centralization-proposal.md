# Proposal: Centralized Dependabot Configuration

## Problem

Dependabot configuration (dependabot.yml) needs to be kept in sync across all microservice repositories. When the configuration changes, it should propagate to all repos without manual effort per repo. Some repos may need repo-specific customizations on top of the shared base config.

## Per-repo customization: Base + local overlay

Dependabot only supports a single `.github/dependabot.yml` per repo — no native inheritance. To allow per-repo customization without losing central management, the sync mechanism (both approaches below) supports an optional local overlay file:

- `.github/dependabot.yml` — **generated, do not edit manually**. Managed by the sync mechanism.
- `.github/dependabot-local.yml` — **optional, repo-specific additions**. Manually maintained.

The sync process:
1. Fetches the base template (e.g. `maven.yml`)
2. If `.github/dependabot-local.yml` exists, merges its `updates` entries into the base using `yq`
3. Writes the combined result to `.github/dependabot.yml`

This lets a repo add extra ecosystems or repo-specific rules without losing automatic updates from the central config. Example local overlay for a repo that also has a Go module:

```yaml
# .github/dependabot-local.yml
updates:
  - package-ecosystem: "gomod"
    directory: "/"
    schedule:
      interval: "monthly"
    target-branch: "develop"
```

The merge concatenates the `updates` lists — base entries first, then local entries. `yq` is lightweight and available on GitHub Actions runners.

---

## Approach A: Push-based — Central distribution script

A script runs from a central location (locally or in CI) and pushes the correct dependabot.yml template to each target repo.

### How it works

1. Templates (one per ecosystem: maven, gradle, pip, github-actions-only) and a repo manifest (`repos.conf`) live in a central repo (e.g. `transitdata-shared-workflows`)
2. Two triggers via GitHub Actions:
   - **On merge to main**: Automatically runs the distribution to all repos
   - **On PR (dry-run)**: Validates the change before merging — reports for each repo whether it can be applied cleanly, whether PRs would be needed, and flags any merge conflicts
3. For each repo in the manifest:
   - Shallow clone the repo
   - Check out the target branch (`develop` or `main`)
   - Copy the appropriate template to `.github/dependabot.yml`
   - If `.github/dependabot-local.yml` exists, merge it into the result using `yq`
   - If no diff → skip
   - If diff and the file applies cleanly → commit and push directly
   - If merge conflict (e.g. someone manually edited the generated file) or branch protection prevents direct push → create a PR instead
4. Supports `--dry-run` and `--repo <name>` flags for local testing

### Central repo structure

```
dependabot-config/
├── distribute.sh
├── templates/
│   ├── maven.yml
│   ├── gradle.yml
│   ├── pip.yml
│   └── github-actions-only.yml
└── repos.conf            # repo-name:template mapping
```

### Validation on PR (dry-run)

When a PR modifies templates or `repos.conf`, a CI workflow runs the script in dry-run mode and posts a summary comment on the PR:
- Which repos would be updated
- Which repos are already up-to-date (no diff)
- Which repos would need a PR due to merge conflicts or branch protection
- Any errors (e.g. repo not found, permission issues)

This gives confidence before merging that the change will apply cleanly.

### Pros

- Simple to understand — one script, automatic on merge
- Validation before merge via dry-run on PRs
- No per-repo setup needed beyond being listed in `repos.conf`
- Direct push when possible (no unnecessary PRs for a config-only file)
- Falls back to PR creation on merge conflicts or branch protection
- Can also be run locally for debugging

### Cons

- Adding a new repo requires updating `repos.conf` in the central repo
- Requires cross-repo push permissions (PAT or GitHub App token)
- Central point of execution — if the script fails mid-run, some repos may be updated and others not (can be mitigated with idempotent re-runs)

---

## Approach B: Pull-based — Scheduled GitHub Action in each repo

Each repo that needs centralized configuration runs a scheduled GitHub Action (via shared workflow) that pulls the latest template from the central repo and commits it if changed.

### How it works

1. Templates live in the central repo (same structure as Approach A)
2. A reusable workflow is defined in `transitdata-shared-workflows`:
   ```yaml
   # .github/workflows/sync-dependabot-config.yml
   name: Sync Dependabot config
   on:
     workflow_call:
       inputs:
         template:
           description: 'Template name (maven, gradle, pip, github-actions-only)'
           required: true
           type: string
         target-branch:
           description: 'Branch to commit to'
           required: false
           default: 'develop'
           type: string
   ```
3. Each consuming repo adds a minimal workflow:
   ```yaml
   # .github/workflows/sync-dependabot-config.yml
   name: Sync Dependabot config
   on:
     schedule:
       - cron: '0 6 * * 1'  # e.g. weekly on Monday at 06:00
     workflow_dispatch:       # allow manual trigger
   jobs:
     sync:
       uses: HSLdevcom/transitdata-shared-workflows/.github/workflows/sync-dependabot-config.yml@main
       with:
         template: maven
       secrets: inherit
   ```
4. The shared workflow:
   - Fetches the template from the central repo (via `gh api` or raw URL)
   - If `.github/dependabot-local.yml` exists in the repo, merges it into the template using `yq`
   - Compares with current `.github/dependabot.yml`
   - If changed: commits and pushes directly to the target branch
   - If branch protection blocks push: creates a PR instead

### Pros

- **Self-healing**: Repos automatically pick up changes on schedule — no one needs to remember to run anything
- **Decentralized execution**: Each repo is responsible for its own sync; failure in one repo doesn't affect others
- Adding the workflow to a new repo is a one-time, minimal setup (3-line workflow file with template parameter)
- The shared workflow itself is distributed via the existing shared-workflows mechanism the team already uses
- Each repo's sync schedule and template choice are visible in its own codebase
- Workflow dispatch allows manual trigger for immediate sync

### Cons

- **Delay**: Changes propagate on the schedule interval (e.g. up to 1 week if weekly), not immediately
  - Mitigated by manual `workflow_dispatch` trigger when urgency is needed
- Requires initial per-repo setup (adding the caller workflow file) — though this is a one-time, small change
- Each repo needs appropriate permissions for the workflow to commit/push
- Slightly more moving parts than a single script

---

## Comparison

| Aspect | A: Push (central script) | B: Pull (scheduled action per repo) |
|--------|--------------------------|--------------------------------------|
| **Propagation** | Automatic on merge to main | Scheduled (automatic) + manual dispatch |
| **Latency** | Immediate on merge | Up to schedule interval (e.g. 1 week) |
| **Per-repo setup** | None (just add to `repos.conf`) | One-time: add ~10-line workflow file |
| **Failure isolation** | One script, all-or-nothing per run | Each repo independent |
| **Visibility** | Central — only in the script repo | Distributed — each repo shows its sync workflow and config |
| **Remembering to run** | Automatic on merge | Automatic on schedule |
| **New repo onboarding** | Add line to `repos.conf` | Add workflow file to repo |
| **Existing patterns** | New script | Extends existing shared-workflows pattern |
| **Cross-repo permissions** | Script needs PAT/token for all repos | Each repo's GITHUB_TOKEN may suffice (if pushing to own repo) |
| **Pre-merge validation** | Dry-run on PR with summary report | No built-in validation |
| **Per-repo customization** | Supported via dependabot-local.yml | Supported via dependabot-local.yml |
