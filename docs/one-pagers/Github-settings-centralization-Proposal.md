# Centralized GitHub Repository Governance for HSL

## What?

We propose building a **centralized GitHub governance solution** that standardizes and enforces repository configuration across all HSL InfoDevOps repositories (100+ services).

The solution will consist of:

- A **version-controlled YAML configuration file** that defines:
    - A **default repository standard**
    - **Per-repository overrides** for exceptional cases

- A **TypeScript-based automation tool** that:
    - Reads the YAML configuration
    - Retrieves current repository settings from GitHub
    - Compares actual vs desired state
    - Applies necessary changes via **GitHub GraphQL and REST APIs**

- Alignment with existing platform standards:
  - **Shared CI/CD workflows** (`transitdata-shared-workflows`)
  - **Standard Docker base images** used across microservices

### Execution Modes

- **Audit** → detect and report configuration drift
- **Plan** → preview changes before applying
- **Apply** → enforce the desired configuration

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

### 1. Define a Central YAML Policy

A single YAML file defines:
- global defaults
- repository-specific overrides

```yaml
organization: HSLdevcom

defaults:
  repository:
    default_branch: main
    features:
      wiki: false
      discussions: false
      projects: false
      auto_merge: true
      delete_head_branch: true

    merge:
      allow_rebase_merge: true
      allow_squash_merge: false
      allow_merge_commit: false

  branch_protection:
    target: main
    require_pull_request: true
    required_approving_review_count: 1
    dismiss_stale_reviews: true
    require_last_push_approval: true
    required_status_checks:
      - Build, check, test, push
    require_conversation_resolution: true
    require_linear_history: true
    allow_force_pushes: false
    allow_deletions: false
    require_merge_queue: true

repositories:
  mqtt-pulsar-gateway: {}

  transitlog-hfp-split-sink:
    repository:
      merge:
        allow_merge_commit: true

  transitdata-metro-ats-parser:
    branch_protection:
      required_status_checks:
        - Build, check, test, push
        - Robot tests
```
#### Key principles
- **Defaults-first model**
- **Overrides only where necessary**
- Empty `{}` means full inheritance

### 2. Build the Governance Tool

#### Technology Choice
- Typescript for long-term maintainability and GitHub ecosystem alignment

### 3. Use GitHub APIs Strategically

#### GraphQL API
Used for:
- retrieving repositories in bulk
- fetching repository metadata efficiently
- handling some mutations (branch protection, rulesets, teams)

#### REST API
Used for:
- repository settings (merge options, features)
- branch protection enforcement
- GitHub Actions configuration
- secrets and integrations
- collaborator and team management

> Recommended approach: GraphQL for querying, REST for enforcement

#### 4. Reconciliation Workflow
For each repository:
1. Load desired configuration (defaults + overrides)
2. Fetch actual state from GitHub
3. Compute differences (drift detection)
4. Apply changes (if in apply mode):
   - repository settings
   - merge strategy
   - branch protection / rulesets
   - Actions policies
   - team permissions
   - CI/CD workflow alignment (`transitdata-shared-workflows`)
   - Docker base image validation

#### 5. Execution Modes

The governance tool supports three execution modes, each serving a distinct purpose in the reconciliation lifecycle.

### Audit Mode
**Purpose:**  
Detect configuration drift without making changes.

**Behavior:**
- Fetches current repository configuration
- Compares it against the desired YAML policy
- Reports differences

**Output:**
- Console logs
- Structured diff report

**Use Cases:**
- Monitoring compliance
- Periodic validation (e.g.: nightly runs)

---

### Plan Mode
**Purpose:**  
Preview changes before applying them.

**Behavior:**
- Computes the exact changes required to reach the desired state
- Does not modify any repository settings

**Output:**
- Detailed change plan
- Can be used for review or approval workflows

**Use Cases:**
- Safe validation before enforcement
- Pull request previews for governance changes

---

### Apply Mode

**Purpose:**  
Enforce the desired configuration.

**Behavior:**
- Applies all required changes via GitHub APIs
- Updates repository settings, branch protections, and policies

**Output:**
- Execution logs
- Summary of applied changes

**Use Cases:**
- Initial standardization rollout
- Continuous enforcement of policy

#### 6. Integration into CI/CD

The tool should run:
- periodically (e.g.: nightly or cron-based job)
- on-demand (manual trigger)
- optionally on policy changes

Outputs:
- logs
- structured diff reports
- optional PR comments or ADO integration

#### 7. Managing exceptions
Exceptions are handled via:
- per-repository overrides
- optional `disabled_controls` flags

Example:

```yaml
repositories:
  mqtt-pulsar-gateway:
    disabled_controls:
      - merge_queue
```

#### 8. Alignment with CI/CD and Runtime Standards
This governance solution extends beyond GitHub settings and ensures:

* CI/CD Standardization
  * All repositories use `transitdata-shared-workflows`
  * Required workflows (eg: `ci-cd.yml`) are enforced
  * Status checks correspond to shared workflows outputs
* Runtime Standardization
  * All services use approved Docker base images
