# Centralized GitHub Repository Governance for HSL

## What?

We propose building a **centralized GitHub governance solution** that standardizes and enforces repository configuration across all HSL InfoDevOps repositories (100+ services).

The solution will consist of:

- A **version-controlled configuration** that defines:
    - A **default repository standard**
    - **Per-repository overrides** for exceptional cases

- The **[Bulk GitHub Repository Settings Sync](https://github.com/marketplace/actions/bulk-github-repository-settings-sync) marketplace action** (v2) as the primary enforcement engine, covering ~80% of the governance scope out of the box

- A **thin custom script** for the remaining ~20% that the marketplace action does not cover:
    - GitHub Actions policies (allowed actions, workflow permissions)
    - Team and collaborator permissions
    - HSL-specific compliance checks (shared-workflows migration status, Docker base image validation)

- Alignment with existing platform standards:
  - **Shared CI/CD workflows** (`transitdata-shared-workflows`)
  - **Standard Docker base images** used across microservices

### Execution Modes

- **Dry-run** → detect and report configuration drift (built into the marketplace action)
- **Apply** → enforce the desired configuration
- **Compliance audit** → HSL-specific validation (shared-workflows, Docker base images) via custom script

### Target State

> All repositories are automatically aligned with HSL InfoDevOps standards, with minimal manual intervention and controlled deviations.

---

## Why?

### 1. Eliminate Manual Configuration

Managing repository settings manually via GitHub UI:
- does not scale to 100+ repositories
- is error-prone
- leads to inconsistencies

Automation ensures:
- repeatability
- reliability
- zero-click standardization

---

### 2. Enforce Consistency Across Microservices

HSL InfoDevOps team operates a large number of microservices that should behave uniformly in terms of:
- CI/CD workflows (via `transitdata-shared-workflows`)
- runtime environments (via standardized Docker base images)
- branch protection rules
- merge strategies
- security controls

Without central governance:
- repositories drift over time
- CI/CD implementations diverge
- runtime inconsistencies appear (e.g., Java version mismatch)
- debugging and maintenance become harder

---

### 3. Improve Developer Experience

A consistent repository setup enables:
- predictable PR workflows
- standardized CI/CD pipelines
- consistent runtime environments
- reliable CI expectations

This is especially important for:
- trunk-based development
- clean Git history (supporting `git bisect`)
- efficient handling of Dependabot PRs

---

### 4. Strengthen Security and Compliance

Central enforcement ensures:
- required CI checks always run (aligned with shared workflows)
- unsafe GitHub Actions usage is restricted
- force pushes and branch deletions are disabled
- required reviews are enforced

Additionally:
- GitHub Apps and secrets can be validated centrally
- Docker base image usage can be standardized and verified
- deviations can be detected early

---

### 5. Support Scalability and Future Growth

With centralized governance:
- onboarding new repositories becomes trivial
- CI/CD standards evolve in one place (`transitdata-shared-workflows`)
- runtime standards evolve via base Docker images
- changes can be rolled out consistently across all services

---

## How?

### Implementation Approach

Following a PR review recommendation, we evaluated the [Bulk GitHub Repository Settings Sync](https://github.com/marketplace/actions/bulk-github-repository-settings-sync) marketplace action as an alternative to building a custom TypeScript tool from scratch.

**Decision: use the marketplace action as the foundation, build a thin custom script only for the gaps.**

The action covers everything in our original scope except GitHub Actions policies, team permissions, and HSL-specific compliance checks. Using it eliminates the need to build and maintain what is already a well-tested, actively maintained open-source tool.

| Concern | Handled by |
|---|---|
| Repo settings (merge, auto-merge, delete branch) | Marketplace action |
| Branch protection (required reviews, linear history, force push, merge queue, status checks) | Marketplace action (via modern rulesets API) |
| Security settings (secret scanning, Dependabot, push protection) | Marketplace action |
| File sync (workflow files, `dependabot.yml`, CODEOWNERS, PR templates) | Marketplace action |
| Environments | Marketplace action |
| GitHub Actions policies | Custom script |
| Team and collaborator permissions | Custom script |
| Shared-workflows migration compliance | Custom script |
| Docker base image compliance | Custom script |

> **Note on rulesets vs classic branch protection:** The marketplace action enforces branch protection via the modern GitHub Rulesets API, which is the direction GitHub is actively investing in. The original proposal used the classic branch protection API. All required settings (required reviewers, dismiss stale reviews, linear history, merge queue, force push protection, etc.) are fully supported via rulesets.

---

### 1. Define the Central Policy

The policy is split into two files:

#### `config/settings-config.yml` — repository settings (rules-based, Option 2)

Uses the action's rules-based format: a list of rules, each with a selector and a set of settings. Later rules override earlier ones for overlapping repositories.

```yaml
owner: HSLdevcom

rules:
  - selector:
      all: true
    settings:
      allow-squash-merge: false
      allow-merge-commit: false
      allow-rebase-merge: true
      allow-auto-merge: true
      delete-branch-on-merge: true
      secret-scanning: true
      secret-scanning-push-protection: true
      dependabot-alerts: true
      dependabot-security-updates: true
      rulesets-file: config/rulesets/default-branch-protection.json
      dependabot-yml: config/dependabot.yml
      pull-request-template: config/pull_request_template.md
      workflow-files: .github/workflows/dependabot-auto-approve.yml

  # Per-repo overrides: only specify what differs from the default above
  - selector:
      repos:
        - HSLdevcom/transitlog-hfp-split-sink
    settings:
      allow-merge-commit: true
```

#### `config/rulesets/default-branch-protection.json` — branch protection ruleset

A standard GitHub Rulesets JSON file defining the `main` branch protection:

```json
{
  "name": "HSL Default Branch Protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_last_push_approval": true,
        "require_code_owner_review": false,
        "required_review_thread_resolution": true
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "required_status_checks": [
          { "context": "Build, check, test, push" }
        ],
        "strict_required_status_checks_policy": false
      }
    },
    { "type": "merge_queue" }
  ]
}
```

Per-repo exceptions that require a different ruleset (e.g., additional status checks) get their own JSON file referenced in the override rule:

```yaml
  - selector:
      repos:
        - HSLdevcom/transitdata-metro-ats-parser
    settings:
      rulesets-file: config/rulesets/default-branch-protection.json,config/rulesets/robot-tests-branch-protection.json
```

#### Key principles
- **Defaults-first model**: a single `all: true` rule sets the baseline
- **Overrides only where necessary**: additional selector rules target only the repos that differ
- **Rulesets as files**: branch protection is version-controlled JSON, not inline YAML

---

### 2. GitHub Actions Workflow

The marketplace action runs as a GitHub Actions workflow in this repository, triggered on push (when the policy changes) and on a nightly schedule.

```yaml
# .github/workflows/github-settings-sync.yml
name: Sync GitHub Repository Settings

on:
  push:
    branches: [main]
    paths:
      - 'config/**'
  schedule:
    - cron: '0 2 * * *'   # nightly drift detection
  workflow_dispatch:
    inputs:
      dry-run:
        description: 'Dry run (detect drift without applying changes)'
        type: boolean
        default: true

jobs:
  sync-settings:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: joshjohanning/github-settings-sync@v2
        with:
          github-token: ${{ secrets.GITHUB_SETTINGS_SYNC_TOKEN }}
          owner: HSLdevcom
          repositories-file: config/settings-config.yml
          dry-run: ${{ inputs.dry-run || false }}
          write-job-summary: true
```

**Authentication:** a GitHub App (preferred over a PAT) with:
- Repository Administration: Read & write
- Contents: Read & write
- Pull Requests: Read & write
- Organization Custom Properties: Read

---

### 3. Custom Compliance Script

A separate, lightweight script handles the three areas the marketplace action does not cover. It runs as a second job in the same workflow.

#### GitHub Actions policies
- Enforce allowed actions settings (e.g., only `HSLdevcom` and trusted publishers)
- Enforce default workflow permissions (read-only, no write by default)

#### Team and collaborator permissions
- Ensure standard team roles are applied consistently across all repos

#### HSL-specific compliance checks
- **Shared-workflows migration**: flag repos still using the old inline `test-and-build.yml` pattern instead of `transitdata-shared-workflows`
- **Docker base image compliance**: flag repos still using `eclipse-temurin:11-alpine` instead of `infodevops-docker-base-images`

The script runs in audit-only mode by default and posts a structured report as a job summary. Remediation for these checks remains manual (guided by the `Microservice-Modernization-Checklist.md`).

---

### 4. Managing Exceptions

#### Settings exceptions (marketplace action)
Per-repo overrides are expressed as additional selector rules in `settings-config.yml`:

```yaml
  - selector:
      repos:
        - HSLdevcom/mqtt-pulsar-gateway
    settings:
      rulesets-file: config/rulesets/no-merge-queue-branch-protection.json
```

#### Compliance exceptions (custom script)
Repos with a documented, intentional deviation are listed in an exceptions file:

```yaml
# config/compliance-exceptions.yml
shared-workflows-migration:
  - HSLdevcom/jore-map-ui       # Not a transitdata service; migration not planned

docker-base-image:
  - HSLdevcom/hsl-map-publisher # Uses custom Node.js base; tracked in separate ticket
```

---

### 5. Integration into CI/CD

The governance workflow runs:
- on every push to `main` in this repo when `config/` changes → immediate enforcement
- nightly → drift detection and compliance reporting
- on-demand via `workflow_dispatch` → manual dry-run or apply

Output:
- GitHub Actions job summary with a before/after table (provided by the marketplace action)
- Compliance report from the custom script
- Failed workflow = configuration drift detected → treated as a signal to investigate

