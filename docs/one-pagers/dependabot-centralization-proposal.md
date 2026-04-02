# Proposal: Centralized Dependabot Configuration

## Problem

Dependabot configuration (dependabot.yml) needs to be kept in sync across all microservice repositories. When the configuration changes, it should propagate to all repos without manual effort per repo. Some repos may need repo-specific customizations on top of the shared base config.

## Solution

Use the [`bulk-github-repo-settings-sync-action`](https://github.com/joshjohanning/bulk-github-repo-settings-sync-action) GitHub Action to push a canonical `dependabot.yml` from a central repo to all team repositories. This is a push-based approach: changes propagate immediately on merge and a daily cron job catches newly created repos.

The Action is maintained by a GitHub employee and supports syncing files (including `dependabot.yml`, workflow files, PR templates, CODEOWNERS) and repository settings across an entire org or a selected set of repos. For file changes, it creates PRs in target repos — no PR is created if the file already matches. If an open PR already exists, it updates the PR branch when the source changes.

## How it works

1. A single canonical `dependabot.yml` lives in a central repo (e.g. `transitdata-shared-workflows`). Dependabot ignores ecosystems that don't apply to a given repo, so one template everywhere simplifies management.
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
dependabot-config/
├── .github/
│   └── workflows/
│       └── sync-dependabot-config.yml
├── settings-config.yml                          # repo targeting rules
└── config/
    └── dependabot/
        ├── default.yml                          # canonical template for all repos
        └── with-gomod.yml                       # variant for repos that also have Go
```

### Example workflow

```yaml
# .github/workflows/sync-dependabot-config.yml
name: Sync Dependabot config
on:
  push:
    branches: [main]
    paths:
      - 'config/dependabot/**'
      - 'settings-config.yml'
      - '.github/workflows/sync-dependabot-config.yml'
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

      - name: Auto-merge created PRs
        if: github.event_name != 'pull_request'
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
        run: |
          # Find open PRs created by the app across target repos
          PR_TITLE="chore: sync dependabot.yml from central config"
          REPOS=$(yq '.rules[].selector.repos // [] | .[]' settings-config.yml 2>/dev/null)
          # Also get repos from custom property selector via API
          REPOS="$REPOS $(gh api "/orgs/HSLdevcom/repos?custom_property_name=team&custom_property_value=infodevops&per_page=100" --jq '.[].full_name')"

          for REPO in $REPOS; do
            PR_NUMBER=$(gh pr list --repo "$REPO" --search "\"$PR_TITLE\" is:open" --json number --jq '.[0].number' 2>/dev/null)
            if [ -n "$PR_NUMBER" ]; then
              echo "Auto-merging $REPO#$PR_NUMBER"
              gh pr merge "$PR_NUMBER" --repo "$REPO" --squash --auto
            fi
          done
```

---

## Auto-merge

With many repositories, manually merging sync PRs is not feasible. The workflow handles this automatically:

1. The sync step creates PRs in repos where `dependabot.yml` differs from the canonical version.
2. A follow-up step finds these PRs by title and enables **GitHub auto-merge** (`gh pr merge --auto --squash`) on each.
3. If the repo has required status checks, the PR merges automatically once checks pass. If no checks are required, the PR merges immediately.

**Prerequisites**:
- **Auto-merge must be enabled** in each repo's settings (Settings > General > Allow auto-merge). The same `bulk-github-repo-settings-sync-action` can enforce this setting across all repos: `auto-merge: true`.
- The GitHub App token needs sufficient permissions (Contents + Pull requests R/W, already covered).

If a repo has required reviews, the PR won't auto-merge until approved. For config-only changes from a trusted bot, consider either:
- Exempting the app from required reviews via a branch ruleset bypass
- Using a ruleset that only requires reviews for non-`.github/dependabot.yml` paths

---

## Validation

Before distributing, the workflow validates the Dependabot YAML against the [official JSON schema](https://json.schemastore.org/dependabot-2.0.json). Options:

- [`marocchino/validate-dependabot`](https://github.com/marocchino/validate-dependabot) — GitHub Action that validates `dependabot.yml`
- [`@bugron/validate-dependabot-yaml`](https://www.npmjs.com/package/@bugron/validate-dependabot-yaml) — npm CLI tool

There is no official Dependabot CLI validator ([open feature request since 2022](https://github.com/dependabot/dependabot-core/issues/4605)). Schema validation catches structural errors (typos, invalid keys, wrong types). Beyond that, Dependabot silently ignores invalid config entries — it won't break anything, it just won't run those rules.

The Action also supports **dry-run mode** — when triggered on a PR to the central repo, it reports what would change without actually creating PRs. This provides pre-merge validation.

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
```

**One-time setup steps**

1. Create a new GitHub App under the HSLdevcom org (Settings > Developer settings > GitHub Apps)
2. Set the permissions listed above (Contents R/W, Pull requests R/W)
3. Install the app on the org (all repos)
4. Generate a private key and note the App ID
5. Store `DEPENDABOT_SYNC_APP_ID` and `DEPENDABOT_SYNC_APP_PRIVATE_KEY` as org-level Actions secrets in `transitdata-shared-workflows`
6. Ensure auto-merge is enabled in target repo settings (can be enforced via the same Action)
