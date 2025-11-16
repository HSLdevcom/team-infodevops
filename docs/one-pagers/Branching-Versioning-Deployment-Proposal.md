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
ghcr.io/org/service:v1.2.0
ghcr.io/org/service:commit-1d4cac8


Deployments reference either immutable version tags (`vX.Y.Z`) or specific commit tags for reproducibility.

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

### 8. Versioning: Public/Partner APIs

- Versioned through **URL prefixing**: `/api/v1/...`
- Increment MAJOR version (`/v2/`) when breaking changes occur.
- Deprecated versions remain accessible for a transition period.

Example:
/api/v1/users
/api/v2/users


---

### 9. Versioning: HSL-internal APIs

- Internal APIs use the same SemVer approach but are coordinated via internal dependency management.
- Changes are reflected in OpenAPI definitions.
- Breaking changes → MAJOR version increment in `/internal/vX/` path.

Example:
/internal/v1/vehicle-status


---

### 10. Versioning: Team-internal APIs

- For intra-team development, explicit versioning may be skipped during early iteration.
- Optional `/dev/` endpoint can be used to indicate unstable contracts.
- Once stabilized, versioning follows the standard `/v1/` scheme.

Example:
/dev/metrics
/v1/metrics


---

### 11. Versioning: Pulsar Topics

To support schema evolution in event-driven systems:

- Add version suffix to topic names: `topic.v1`, `topic.v2`
- Increment version when schema or serialization changes are not backward compatible.
- Schema changes follow **SchemaVer** (`MAJOR-MINOR-PATCH`) for consistency with JSON schema management.

Example:
vehicle.events.v1
vehicle.events.v2


---

## Summary

| Aspect | Decision |
|--------|-----------|
| **Branching** | Trunk-based (`main` only, short-lived features) |
| **Version Scheme** | Semantic Versioning (SemVer) |
| **Git Tags** | `vX.Y.Z`, `vX.Y.Z-rc` |
| **Docker Tags** | `:commit-sha`, `:vX.Y.Z` |
| **Deployments** | GitOps or pipeline-driven promotion between environments |
| **Hot-fixes** | Cherry-pick + patch release |
| **CAB** | Mandatory before production |
| **API Versioning** | `/v1/`, `/v2/`, internal `/internal/v1/`, optional `/dev/` |
| **Pulsar Topics** | `topic.v1`, `topic.v2` using SchemaVer |

---

## Expected Outcomes

- Consistent flow from code → tag → deployment
- Faster environment promotion with fewer manual errors
- Reliable and traceable version history
- Simplified hot-fix process
- Transparent CAB-governed production releases
- Clear API and message schema versioning across all integration points