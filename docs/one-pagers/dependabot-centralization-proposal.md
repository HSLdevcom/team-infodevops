# Proposal: Centralized Dependabot Configuration

## Problem

Dependabot configuration (dependabot.yml) needs to be kept in sync across all microservice repositories. When the configuration changes, it should propagate to all repos without manual effort per repo. Some repos may need repo-specific customizations on top of the shared base config.

## Solution

Use the [`bulk-github-repo-settings-sync-action`](https://github.com/joshjohanning/bulk-github-repo-settings-sync-action) GitHub Action to push a canonical `dependabot.yml` from a central repo to all team repositories. This is a push-based approach: changes propagate immediately on merge and a daily cron job catches newly created repos.

The Action is maintained by a GitHub employee and supports syncing files (including `dependabot.yml`, workflow files, PR templates, CODEOWNERS) and repository settings across an entire org or a selected set of repos. For file changes, it creates PRs in target repos — no PR is created if the file already matches. If an open PR already exists, it updates the PR branch when the source changes.

## How it works

1. A single canonical `dependabot.yml` lives in a central repo (e.g. `infodevops-github-policy`). Dependabot ignores ecosystems that don't apply to a given repo, so one template everywhere simplifies management.
2. A GitHub Actions workflow in the central repo runs the Action with two triggers:
   - **On merge to main**: Immediately syncs the config to all target repos
   - **On schedule (daily cron)**: Catches newly created repos and corrects drift
3. The Action compares each target repo's `.github/dependabot.yml` with the canonical version. If it differs, a PR is created (or an existing open PR is updated). If identical, the repo is skipped.
4. A follow-up step auto-merges the created PRs (see [Auto-merge](#auto-merge) below).
5. Archived repos are automatically skipped by the Action.

### Repository targeting

Two options for selecting which repos to sync:

**Option A — Repo list (`repos.yml`)**: List repos explicitly, with optional per-repo overrides.

```yaml
repos:
  - repo: HSLdevcom/transitdata-hfp-parser
  - repo: HSLdevcom/transitdata-cancellation-processor
  - repo: HSLdevcom/transitdata-gtfsrt-full-publisher
    dependabot-yml: './config/dependabot/with-gomod.yml'  # per-repo override
```

**Option B — Rules-based (`settings-config.yml`)**: Target repos dynamically using GitHub custom properties. Later rules override earlier ones for the same setting.

```yaml
owner: HSLdevcom
rules:
  - selector:
      custom-property:
        name: team
        values: [infodevops]
    settings:
      dependabot-yml: './config/dependabot/default.yml'
  - selector:
      repos: [HSLdevcom/transitdata-gtfsrt-full-publisher]
    settings:
      dependabot-yml: './config/dependabot/with-gomod.yml'
```

Option B is preferred — it automatically includes new repos when the `team` custom property is set, and per-repo overrides are handled via explicit repo selectors. No denylist or manifest to maintain.

### Central repo structure

```
infodevops-github-policy/
├── .github/
│   └── workflows/
│       └── sync.yml
├── settings-config.yml                          # repo targeting rules
└── config/
    └── dependabot/
        ├── default.yml                          # canonical template for all repos
        └── with-gomod.yml                       # variant for repos that also have Go
```

### Example workflow

```yaml
# .github/workflows/sync.yml
name: Sync Dependabot config
on:
  push:
    branches: [main]
    paths:
      - 'config/dependabot/**'
      - 'settings-config.yml'
      - '.github/workflows/sync.yml'
  schedule:
    - cron: '0 6 * * *'  # daily at 06:00 UTC
  workflow_dispatch:

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/create-github-app-token@v1
        id: app-token
        with:
          app-id: ${{ secrets.DEPENDABOT_SYNC_APP_ID }}
          private-key: ${{ secrets.DEPENDABOT_SYNC_APP_PRIVATE_KEY }}
          owner: HSLdevcom

      - name: Sync Dependabot config
        uses: joshjohanning/bulk-github-repo-settings-sync-action@v2
        with:
          github-token: ${{ steps.app-token.outputs.token }}
          repositories-file: 'settings-config.yml'
          dependabot-pr-title: 'chore: sync dependabot.yml from central config'
          dry-run: ${{ github.event_name == 'pull_request' }}
```

---

## Auto-merge

With many repositories, manually merging sync PRs is not feasible. Rather than handle this from the policy repo workflow, the merging logic lives in each microservice repo. Two pieces are bootstrapped into every microservice as part of the harmonization effort (and then kept in sync via this same `bulk-github-repo-settings-sync-action`):

1. **Repo settings**: auto-merge enabled (Settings > General > Allow auto-merge) and the branch protection rule set to auto-merge once CI passes and the PR is approved. Enforced across all repos via `auto-merge: true` on the sync action.
2. **Auto-approve workflow**: a canonical workflow (e.g. `.github/workflows/auto-approve-github-policy.yml`) that auto-approves PRs opened by the policy GitHub App. This is itself one of the canonical files distributed by the policy repo.

With those in place, a sync PR opened in a microservice is auto-approved by the workflow, passes CI, and is auto-merged by the repo setting — no orchestration needed from the policy repo workflow.

**Bootstrap caveat**: the first time a repo joins the system, the auto-approve workflow has to land before sync PRs can auto-merge. Either bootstrap the repo with the canonical workflow file first, or approve the initial sync PR manually.

---

## Authentication: GitHub App

Cross-repo write access is needed. A **dedicated GitHub App** is the recommended mechanism — it avoids tying permissions to any individual developer account.

**Why a GitHub App over a PAT**

- Not tied to any individual — the app is an org-level resource
- Minimal, explicitly scoped permissions (least-privilege)
- Short-lived installation tokens (1 hour), automatically rotated
- Clear bot identity in commits (`<app-name>[bot]`)
- Full traceability via GitHub audit log

**App permissions (least-privilege)**

| Permission | Access | Why |
|---|---|---|
| Contents | Read & Write | Read repos and push config via PRs |
| Pull requests | Read & Write | Create and auto-merge PRs in target repos |
| Metadata | Read-only | Implicit with any app installation |

**Installation scope**

Install on **all org repos** (simplest) — new repos are automatically covered, no maintenance needed. Repo targeting is handled by the rules-based config.

**Secrets management**

Store two secrets as **org-level GitHub Actions secrets** in `infodevops-github-policy`:

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
```

**One-time setup steps**

1. Create a new GitHub App under the HSLdevcom org (Settings > Developer settings > GitHub Apps)
2. Set the permissions listed above (Contents R/W, Pull requests R/W)
3. Install the app on the org (all repos)
4. Generate a private key and note the App ID
5. Store `DEPENDABOT_SYNC_APP_ID` and `DEPENDABOT_SYNC_APP_PRIVATE_KEY` as org-level Actions secrets in `infodevops-github-policy`
6. Ensure auto-merge is enabled in target repo settings (can be enforced via the same Action)
