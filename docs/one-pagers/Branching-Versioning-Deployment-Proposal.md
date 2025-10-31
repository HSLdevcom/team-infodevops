# One Pager: Design Proposal for Branching, Versioning, and Deployment

## What?

To improve development speed, consistency, and deployment safety, this proposal defines a standard approach for:

- Git branching
- Version number scheme
- Git and Docker tags
- Deployment promotion between environments
- Security hot-fixes
- CAB approval process
- Versioning of APIs and Pulsar topics

The design aims to reduce manual work, limit human errors, and ensure reliable traceability from commit → Docker image → environment deployment.

---

## Why?

Currently, branching, versioning, and deployment practices vary across teams.  
This inconsistency causes:

- Merge conflicts and confusion about release readiness
- Manual effort during environment promotion
- Difficulty applying security hot-fixes
- Limited traceability of deployed versions
- Risk of deploying unapproved code to production

By adopting a consistent approach—centered around **trunk-based development**, **semantic versioning**, and **automated Docker tagging**—we gain predictable flow, simplified hot-fix handling, and controlled CAB-approved releases.

---

## How?

### 1. Git Branches

We adopt **trunk-based development** ([https://trunkbaseddevelopment.com/](https://trunkbaseddevelopment.com/)):

- `main` is the **single long-lived branch**.
- Developers create short-lived feature branches → merged into `main` via PRs after review.
- The **development environment** automatically follows the `main` branch.
- **Staging** and **Production** deployments are based on Git tags.

**Rationale:**  
Having persistent, parallel environment branches (e.g., `staging`, `prod`) adds maintenance overhead without reducing the need for cherry-picking hot-fixes. Trunk-based flow simplifies both merging and automation.

---

### 2. Version Number Scheme

Use **Semantic Versioning (SemVer)**:  
`MAJOR.MINOR.PATCH`

| Level | Trigger | Example |
|--------|----------|----------|
| MAJOR | Breaking API or schema change | 2.0.0 |
| MINOR | Backward-compatible feature | 1.2.0 |
| PATCH | Bug or security fix | 1.2.3 |

This version number is applied consistently across:

- Git tags (`v1.2.3`)
- Docker image tags (`:v1.2.3`)
- Deployment metadata
- Release notes

---

### 3. Git Tags

Git tags define deployment points.

| Tag Type | Example | Purpose |
|-----------|----------|----------|
| Release | `v1.2.0` | Production-ready version |
| Release Candidate | `v1.2.0-rc` | Staging pre-release |
| Hot-fix | `v1.2.1` | Urgent patch or security update |

Tags are created from commits on `main`.  
These tags automatically trigger Docker builds and deployments for staging and production.  
Releases and CAB decisions refer to these tags for auditability.

---

### 4. Docker Tags

Docker tags mirror Git commit and versioning states for clear traceability.

Each image built from CI/CD gets:

- **Commit tag:** `:<git-sha>` — exact build traceability
- **Version tag:** `:vX.Y.Z` — immutable release version

**Example:**
