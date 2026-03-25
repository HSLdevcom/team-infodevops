# Proposal: Centralized Dependabot Configuration

## Problem

Dependabot configuration (dependabot.yml) needs to be kept in sync across all microservice repositories. When the configuration changes, it should propagate to all repos without manual effort per repo. Some repos may need repo-specific customizations on top of the shared base config.

## Per-repo customization: Base + local overlay

Dependabot only supports a single `.github/dependabot.yml` per repo — no native inheritance. To allow per-repo customization without losing central management, the sync mechanism (both approaches below) supports an optional local overlay file:

- `.github/dependabot.yml` — **generated, do not edit manually**. Managed by the sync mechanism.
- `.github/dependabot-local.yml` — **optional, repo-specific additions**. Manually maintained.

The sync process:
1. Fetches the unified base template
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
    target-branch: "main"
```

The merge concatenates the `updates` lists — base entries first, then local entries. `yq` is lightweight and available on GitHub Actions runners.

---

## Approach A: Push-based — Central distribution script

A script runs from a central location (locally or in CI) and pushes the correct dependabot.yml template to each target repo.

### How it works

1. A single unified template (`dependabot.yml`) and a repo manifest (`repos.conf`) live in a central repo (e.g. `transitdata-shared-workflows`). Dependabot ignores ecosystems that don't apply to a given repo, so one template everywhere simplifies management.
2. Two triggers via GitHub Actions:
   - **On merge to main**: Automatically runs the distribution to all repos
   - **On PR (dry-run)**: Validates the change before merging — reports for each repo whether it can be applied cleanly, whether PRs would be needed, and flags any merge conflicts
3. For each repo in the manifest:
   - Shallow clone the repo
   - Check out the default branch (`main`)
   - Copy the unified template to `.github/dependabot.yml`
   - If `.github/dependabot-local.yml` exists, merge it into the result using `yq`
   - If no diff → skip
   - If diff and the file applies cleanly → commit and push directly
   - If merge conflict (e.g. someone manually edited the generated file) or branch protection prevents direct push → create a PR instead
4. Supports `--dry-run` and `--repo <name>` flags for local testing

### Central repo structure

```
dependabot-config/
├── distribute.sh
├── dependabot.yml        # single unified template for all repos
└── repos.conf            # list of target repo names
```

### Validation on PR (dry-run)

When a PR modifies the template or `repos.conf`, a CI workflow runs the script in dry-run mode and posts a summary comment on the PR:
- Which repos would be updated
- Which repos are already up-to-date (no diff)
- Which repos would need a PR due to merge conflicts or branch protection
- Any errors (e.g. repo not found, permission issues)

This gives confidence before merging that the change will apply cleanly.

### Pros

- Simple to understand — one script, automatic on merge
- Validation before merge via dry-run on PRs
- No per-repo setup needed beyond being listed in `repos.conf` (just a repo name, no template mapping)
- Direct push when possible (no unnecessary PRs for a config-only file)
- Falls back to PR creation on merge conflicts or branch protection
- Can also be run locally for debugging

### Cons

- Adding a new repo requires updating `repos.conf` in the central repo
- Requires a dedicated GitHub App for cross-repo push permissions (see Authentication section below)
- Central point of execution — if the script fails mid-run, some repos may be updated and others not (can be mitigated with idempotent re-runs)

### Authentication: GitHub App

The push model requires cross-repo write access. A **dedicated GitHub App** is the recommended mechanism — it avoids tying permissions to any individual developer account.

**Why a GitHub App over a PAT**

- Not tied to any individual — the app is an org-level resource
- Minimal, explicitly scoped permissions (least-privilege)
- Short-lived installation tokens (1 hour), automatically rotated
- Clear bot identity in commits (`<app-name>[bot]`)
- Full traceability via GitHub audit log

**App permissions (least-privilege)**

| Permission | Access | Why |
|---|---|---|
| Contents | Read & Write | Clone repos and push config commits |
| Pull requests | Read & Write | Create PRs when branch protection blocks direct push |
| Metadata | Read-only | Implicit with any app installation |

**Installation scope**

Two options:

- **All org repos** (simplest) — new repos are automatically covered, no maintenance needed
- **Selected repos only** (tighter control) — requires manually adding each new repo to the app's install list

**Secrets management**

Store two secrets as **org-level GitHub Actions secrets** in `transitdata-shared-workflows`:

- `DEPENDABOT_SYNC_APP_ID` — the numeric ID of the GitHub App
- `DEPENDABOT_SYNC_APP_PRIVATE_KEY` — the PEM private key generated during app creation

**Token generation in the workflow**

Use the [`actions/create-github-app-token`](https://github.com/actions/create-github-app-token) action to exchange the app credentials for a short-lived installation token:

```yaml
- uses: actions/create-github-app-token@v1
  id: app-token
  with:
    app-id: ${{ secrets.DEPENDABOT_SYNC_APP_ID }}
    private-key: ${{ secrets.DEPENDABOT_SYNC_APP_PRIVATE_KEY }}
    owner: HSLdevcom

- uses: actions/checkout@v4
  with:
    repository: HSLdevcom/${{ matrix.repo }}
    token: ${{ steps.app-token.outputs.token }}
```

**Git identity**

Commits appear as `<app-name>[bot] <DEPENDABOT_SYNC_APP_ID+<app-name>[bot]@users.noreply.github.com>`, making automated changes clearly distinguishable from human commits.

**One-time setup steps**

1. Create a new GitHub App under the HSLdevcom org (Settings → Developer settings → GitHub Apps)
2. Set the permissions listed above (Contents R/W, Pull requests R/W)
3. Install the app on the org (all repos or selected repos)
4. Generate a private key and note the App ID
5. Store `DEPENDABOT_SYNC_APP_ID` and `DEPENDABOT_SYNC_APP_PRIVATE_KEY` as org-level Actions secrets in `transitdata-shared-workflows`

---

## Approach B: Pull-based — Scheduled GitHub Action in each repo

Each repo that needs centralized configuration runs a scheduled GitHub Action (via shared workflow) that pulls the latest template from the central repo and commits it if changed.

### How it works

1. The single unified template lives in the central repo (same structure as Approach A)
2. A reusable workflow is defined in `transitdata-shared-workflows`:
   ```yaml
   # .github/workflows/sync-dependabot-config.yml
   name: Sync Dependabot config
   on:
     workflow_call:
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
       secrets: inherit
   ```
4. The shared workflow:
   - Fetches the unified template from the central repo (via `gh api` or raw URL)
   - If `.github/dependabot-local.yml` exists in the repo, merges it into the template using `yq`
   - Compares with current `.github/dependabot.yml`
   - If changed: commits and pushes directly to the target branch
   - If branch protection blocks push: creates a PR instead

### Pros

- **Self-healing**: Repos automatically pick up changes on schedule — no one needs to remember to run anything
- **Decentralized execution**: Each repo is responsible for its own sync; failure in one repo doesn't affect others
- Adding the workflow to a new repo is a one-time, minimal setup (short workflow file, no parameters needed)
- The shared workflow itself is distributed via the existing shared-workflows mechanism the team already uses
- Each repo's sync schedule and template choice are visible in its own codebase
- Workflow dispatch allows manual trigger for immediate sync

### Cons

- **Delay**: Changes propagate on the schedule interval (e.g. up to 1 week if weekly), not immediately
  - Mitigated by manual `workflow_dispatch` trigger when urgency is needed
- Requires initial per-repo setup (adding the caller workflow file) — though this is a one-time, small change
- Each repo needs appropriate permissions for the workflow to commit/push (though the default `GITHUB_TOKEN` is sufficient — no extra secrets or app setup required)
- Slightly more moving parts than a single script

### Authentication note

The pull model has a simpler auth story: each repo's workflow uses its own `GITHUB_TOKEN` (automatically provided by GitHub Actions) to push to itself. No dedicated GitHub App, PAT, or org-level secrets are needed. If the central template repo is public (or within the same org), fetching templates requires no extra credentials either.

---

## Comparison

| Aspect | A: Push (central script) | B: Pull (scheduled action per repo) |
|--------|--------------------------|--------------------------------------|
| **Propagation** | Automatic on merge to main | Scheduled (automatic) + manual dispatch |
| **Latency** | Immediate on merge | Up to schedule interval (e.g. 1 week) |
| **Per-repo setup** | None (just add repo name to `repos.conf`) | One-time: add ~10-line workflow file |
| **Failure isolation** | One script, all-or-nothing per run | Each repo independent |
| **Visibility** | Central — only in the script repo | Distributed — each repo shows its sync workflow and config |
| **Remembering to run** | Automatic on merge | Automatic on schedule |
| **New repo onboarding** | Add line to `repos.conf` | Add workflow file to repo |
| **Existing patterns** | New script | Extends existing shared-workflows pattern |
| **Cross-repo permissions** | Dedicated GitHub App (Contents + PRs write); no personal PAT needed | Each repo's `GITHUB_TOKEN` suffices (pushing to own repo) |
| **Pre-merge validation** | Dry-run on PR with summary report | No built-in validation |
| **Per-repo customization** | Supported via dependabot-local.yml | Supported via dependabot-local.yml |
