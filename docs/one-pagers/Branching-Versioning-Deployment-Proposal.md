# One Pager: Design Proposal for Branching, Versioning, and Deployment

## What?

To improve development speed, consistency, and deployment safety, this proposal defines a standard approach for:

- Git branching
- Version number scheme
- Git and Docker tags
- Deployment promotion between environments
- Security hot-fixes
- CAB approval process

API and Pulsar topic versioning are covered in a [separate proposal](./API-Pulsar-Versioning-Proposal.md).

The design aims to reduce manual work, limit human errors, and ensure reliable traceability from commit → Docker image → environment deployment.

---

## Why?

Currently, branching, versioning, and deployment practices vary across repositories.  
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

[See Trunk Based Development Migration Plan Proposal](./Trunk-Based-Development-Migration-Plan-Proposal.md)

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
- Docker image tags (`:1.2.3`)
- Deployment metadata
- Release notes

---

### 3. Git Tags

Git tags define deployment points.

| Tag Type | Example | Purpose |
|-----------|----------|----------|
| Release | `v1.2.0` | Stable version for staging and production |
| Patch | `v1.2.1` | Bug fix or security update |

Tags are created from commits on `main`.
These tags trigger Docker image builds. Both staging and production deploy from these version tags.
Releases and CAB decisions refer to these tags for auditability.

---

### 4. Docker Tags

Docker tags mirror Git commit and versioning states for clear traceability.

Each image built from CI/CD gets:

- **Commit tag:** `:sha-<short-sha>` — exact build traceability
- **Version tag:** `:X.Y.Z` — immutable release version (no `v` prefix)
- **Edge tag:** `:edge` — rolling tag updated on every merge to `main`

**Example:**
```
ghcr.io/org/service:edge
ghcr.io/org/service:1.2.0
ghcr.io/org/service:sha-1d4cac8
```

The `edge` tag tracks the latest `main` commit and is used by the development environment. Version tags (`X.Y.Z`) are immutable and used by staging and production.

---

### 5. Deployment Process (Environment Promotion)

| Environment | Source | Trigger | Tag | CAB Required | Notes |
|--------------|---------|----------|------|----------------|-------|
| **Development** | `main` branch | Auto on merge | commit SHA | No | Continuous deployment of latest commits |
| **Production** | `main` branch | Manual promotion | `vX.Y.Z` | Yes | Immutable release deployment |

Promotion between environments is handled via:

- Git tag creation or image promotion

Rollback is straightforward: re-deploy a previous tag (`v1.1.4`).

---

### 6. Security Hot-fixes

- All **Dependabot** or manual security PRs target the default (`main`) branch.
- Urgent production fixes are **cherry-picked** from `main` onto the currently deployed production tag’s base commit.
- A new **patch version tag** (`v1.2.1`) is created and deployed directly to production.
- Normal development continues on `main` uninterrupted.

This ensures critical fixes reach production fast, without merging unfinished features.

---

### 7. CAB Meetings

- CAB meetings are held before production deployments.
- CAB decisions explicitly approve a Git tag (e.g., `v1.2.0`).
- The deployment process uses this approved tag for production rollout.
- CAB records link back to the tag and its changelog for traceability.

---

## Summary

| Aspect | Decision |
|--------|-----------|
| **Branching** | Trunk-based (`main` only, short-lived features) |
| **Version Scheme** | Semantic Versioning (SemVer) |
| **Git Tags** | `vX.Y.Z` |
| **Docker Tags** | `:edge`, `:X.Y.Z`, `:sha-<short-sha>` |
| **Deployments** | GitOps or pipeline-driven promotion between environments |
| **Hot-fixes** | Cherry-pick + patch release |
| **CAB** | Mandatory before production |

---

## Expected Outcomes

- Consistent flow from code → tag → deployment
- Faster environment promotion with fewer manual errors
- Reliable and traceable version history
- Simplified hot-fix process
- Transparent CAB-governed production releases
