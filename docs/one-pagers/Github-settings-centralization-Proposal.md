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

**Decision: use the marketplace action as the foundation for settings enforcement, build a thin custom script for the gaps. File sync is explicitly out of scope for third-party tooling.**

The action covers the pure settings and rulesets part of our scope. Using it eliminates the need to build and maintain what is already a well-tested, actively maintained open-source tool.

#### Trust and supply chain

This central management repository has write access to every HSL repository's branch protection, security settings, and CI/CD configuration. Any action or script running here is a high-value supply chain target. Therefore:

- **Third-party tools must not be used for file propagation** (copying workflow files, `dependabot.yml`, CODEOWNERS, etc. to other repos). This is analogous to tools like [Repo File Sync Action](https://github.com/marketplace/actions/repo-file-sync-action) which we explicitly do not trust for this purpose. The same risk applies to the file sync capability of the marketplace action — it is **not used** here.
- **The marketplace action is used solely for settings and ruleset enforcement** (pure API calls to GitHub). This is a more contained, auditable use.
- **The marketplace action must be forked into the `HSLdevcom` org** before use. The upstream action (`joshjohanning/bulk-github-repository-settings-sync`) is authored by an individual developer, not by GitHub. Forking gives us full control over the code that runs with organisation-wide write permissions and eliminates exposure to upstream supply chain compromise.
- **All third-party actions (including the forked one) are pinned to an exact commit SHA**, never a mutable tag.

| Concern | Handled by |
|---|---|
| Repo settings (merge, auto-merge, delete branch) | Marketplace action (forked + SHA-pinned) |
| Branch protection (required reviews, linear history, force push, merge queue, status checks) | Marketplace action (via modern rulesets API) |
| Security settings (secret scanning, Dependabot, push protection) | Marketplace action |
| Environments | Marketplace action |
| File sync (workflow files, `dependabot.yml`, CODEOWNERS, PR templates) | **Out of scope** — not trusted to third-party tools |
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
      # file sync inputs (dependabot-yml, workflow-files, pull-request-template, codeowners)
      # are intentionally not used — see trust rationale in Implementation Approach

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

      - uses: HSLdevcom/github-settings-sync@<commit-sha>  # fork of joshjohanning/bulk-github-repository-settings-sync
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

### 5. Security of the Central Management Repository

Because a single compromised commit to this repo can affect every HSL repository, the central management repo itself must be held to a higher security standard than the services it governs.

#### Repository visibility

Make the repository **private**. This prevents anyone outside the GitHub organisation from opening PRs, browsing the policy configuration, or discovering the scope of write access granted to the GitHub App.

#### CODEOWNERS

A `CODEOWNERS` file lists all InfoDevOps team members. Every file in the repository is owned by the team:

```
# CODEOWNERS
* @HSLdevcom/infodevops-team
```

#### Branch protection on `main`

Configure the following on the `main` branch, with **no bypass actors** — not even org admins:

- Require **2 approving reviews** from different CODEOWNERS before merge
- Dismiss stale reviews on new push
- Require last push approval (prevent self-approval of own final commit)
- Require conversation resolution
- Require linear history
- Block force pushes and branch deletion
- Require all status checks to pass before merge

The "no bypass" constraint is intentional: if the policy governing all repos can be force-merged by one person, the entire governance model is undermined.

#### Additional hardening

- **Restrict who can trigger `workflow_dispatch`**: only team members, not all repo contributors
- **Audit log**: enable organisation audit log streaming so all pushes and workflow runs on this repo are retained
- **Secret access**: the GitHub App token used by the workflow is scoped to the minimum permissions needed; it is stored as an organisation secret accessible only to this repo

---

### 6. Integration into CI/CD

The governance workflow runs:
- on every push to `main` in this repo when `config/` changes → immediate enforcement
- nightly → drift detection and compliance reporting
- on-demand via `workflow_dispatch` → manual dry-run or apply

Output:
- GitHub Actions job summary with a before/after table (provided by the marketplace action)
- Compliance report from the custom script
- Failed workflow = configuration drift detected → treated as a signal to investigate

