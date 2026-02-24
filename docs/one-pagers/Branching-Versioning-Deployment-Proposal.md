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

A [Git branch is a lightweight movable pointer to a commit](https://git-scm.com/book/en/v2/Git-Branching-Branches-in-a-Nutshell), not a sequence of commits. We use branches as follows:

- **`main`** — the single long-lived branch (trunk). All integration happens here.
- **Feature branches** — short-lived branches for work in progress. Merged to `main` via pull request and then deleted.
- **`fix/` branches** — short-lived branches for urgent production fixes (see section 6). Deleted once the patch tag exists.

We adopt **trunk-based development** ([https://trunkbaseddevelopment.com/](https://trunkbaseddevelopment.com/)).

[See Trunk Based Development Migration Plan Proposal](./Trunk-Based-Development-Migration-Plan-Proposal.md)

---

### 2. Version Number Scheme

Based on [**Semantic Versioning 2.0.0 (SemVer)**](https://semver.org/spec/v2.0.0.html):  
`MAJOR.MINOR.PATCH`

| Level | Trigger | Example |
|--------|----------|----------|
| MAJOR | Breaking API or schema change | 2.0.0 |
| MINOR | Regular release from `main` (features, improvements, bug fixes) | 1.2.0 |
| PATCH | Hot-fix to a specific release (see section 6) | 1.2.1 |

#### Convention: MINOR for releases, PATCH for hot-fixes

Regular releases from `main` always bump at least **MINOR**. **PATCH** is reserved exclusively for hot-fixes applied to a specific release via a `fix/` branch.

**Why?** When multiple environments run different versions, PATCH-level releases would create version conflicts. Consider:

```
staging:      1.3.0
production:   1.2.0
```

If production needs an urgent fix, it is tagged as `v1.2.1`. This is unambiguous: `1.2.1` is a patch to `1.2.0` and has nothing to do with `1.3.0`. Staging can independently receive its own fix as `v1.3.1` if needed.

If instead both staging and production used PATCH for regular releases (e.g., staging at `1.2.4`, production at `1.2.3`), a hot-fix to production could not use `1.2.5` without implying it contains `1.2.4`'s changes, which it does not. SemVer provides no suffix or modifier that resolves this: pre-release versions (e.g., `1.2.4-hotfix.1`) have *lower* precedence than `1.2.4` in SemVer, and build metadata (e.g., `1.2.4+hotfix.1`) is ignored for precedence entirely.

By reserving PATCH for hot-fixes, each MINOR release gets its own isolated patch space and no version conflicts can occur between environments.

**SemVer deviation:** Our versioning is based on SemVer 2.0.0 with one deliberate deviation from rule 6. The spec says PATCH MUST be incremented when only backwards-compatible bug fixes are introduced. We bump MINOR instead, to preserve the version space isolation described above. This is defensible because: (1) SemVer was designed for libraries where consumers resolve version ranges — for deployed services, there is no dependency resolution; (2) rule 7 already allows MINOR releases to include patch-level changes, so the semantic signal is only slightly stretched; and (3) in trunk-based development, bug-fix-only releases from `main` are rare — nearly every release includes at least some new functionality.

This version number is applied consistently across:

- Git tags (`v1.2.3`)
- Docker image tags (`:1.2.3`)
- Deployment metadata
- Release notes

Version bumps are currently a **manual decision** by the developer or team when creating a release tag. The target is to adopt [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) for commit messages (tools like [commitizen](https://github.com/commitizen/cz-cli) can help enforce the format). Automating version bumps and changelogs based on Conventional Commits (e.g., via [semantic-release](https://github.com/semantic-release/semantic-release)) is deferred to a separate proposal.

---

### 3. Git Tags

Git tags define deployment points.

| Tag Type | Example | Purpose |
|-----------|----------|----------|
| Release | `v1.2.0` | Regular release from `main` for staging and production |
| Patch | `v1.2.1` | Hot-fix to a specific release via a `fix/` branch |

Tags are created from commits on `main` (releases) or from `fix/` branches (patches).
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

#### Current state

We currently have two environments: development and production.

| Environment | Source | Trigger | Docker Tag | CAB Required | Notes |
|--------------|---------|----------|------------|----------------|-------|
| **Development** | `main` | Auto on merge | `edge` | No | Rolling deployment of latest `main` |
| **Production** | `main` | Manual promotion | `X.Y.Z` | Yes | Immutable release deployment |

Current promotion flow:

1. Every merge to `main` automatically deploys to **development** via the `edge` Docker tag.
2. When a release is ready, a Git tag (`vX.Y.Z`) is created on `main`, producing an immutable Docker image tagged `X.Y.Z`.
3. After CAB approval, the `X.Y.Z` image is deployed to **production**.

Rollback is manual: re-deploy a previous version tag (e.g., `1.1.0`).

#### Target state

A **staging** environment will be added between development and production. Production becomes a delayed version of staging: every version deployed to production has first been validated in staging.

| Environment | Source | Trigger | Docker Tag | CAB Required | Notes |
|--------------|---------|----------|------------|----------------|-------|
| **Development** | `main` | Auto on merge | `edge` | No | Rolling deployment of latest `main` |
| **Staging** | `main` | Git tag `vX.Y.Z` | `X.Y.Z` | No | Validates a release before production |
| **Production** | `main` | Manual promotion | `X.Y.Z` | Yes | Same version tag as staging, after CAB approval |

Target promotion flow:

1. Every merge to `main` automatically deploys to **development** via the `edge` Docker tag.
2. When a release is ready, a Git tag (`vX.Y.Z`) is created on `main`, producing an immutable Docker image tagged `X.Y.Z`.
3. The `X.Y.Z` image is deployed to **staging** for validation.
4. After CAB approval, the same `X.Y.Z` image is promoted to **production**.

Rollback is manual: re-deploy a previous version tag (e.g., `1.1.0`).

---

### 6. Hot-fixes

When an urgent fix is needed in production:

1. The fix is developed on a short-lived **`fix/` branch** (e.g., `fix/auth-token-expiry`) created from the commit that the current production tag points to.
2. The fix is also merged to `main` so trunk stays ahead.
3. A new **PATCH version tag** (e.g., `v1.2.1`) is created on the `fix/` branch. Because regular releases always bump MINOR, the PATCH space is available exclusively for hot-fixes (see section 2).
4. The resulting Docker image (`1.2.1`) is deployed to production (and staging, once available).
5. The `fix/` branch is **deleted** once the patch tag is in place.

The `fix/` branch is short-lived (days to weeks at most). It exists only until the next regular release from `main` includes the same fix, at which point production catches up with trunk.

If multiple environments need the same fix, each environment's current MINOR release is patched independently (e.g., production at `1.2.0` gets `v1.2.1`, staging at `1.3.0` gets `v1.3.1`). This avoids version conflicts between environments.

All **Dependabot** or manual security PRs target `main`. If the fix is urgent enough to bypass the normal release cycle, the `fix/` branch process above is used.

The `fix/` prefix aligns with the `fix:` type in [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

---

### 7. CAB Meetings

- CAB meetings are held before promoting a release to production.
- CAB decisions explicitly approve a Git tag (e.g., `v1.2.0`) for production deployment.
- The deployment process promotes the approved Docker image (`1.2.0`) to production.
- CAB records link back to the tag and its changelog for traceability.
- Once a staging environment exists, the version will have been validated there before CAB review.

---

## Summary

| Aspect | Decision |
|--------|-----------|
| **Branching** | Trunk-based (`main` only, short-lived feature and `fix/` branches) |
| **Version Scheme** | [SemVer 2.0.0](https://semver.org/spec/v2.0.0.html): MINOR for releases, PATCH for hot-fixes only |
| **Git Tags** | `vX.Y.Z` (releases from `main`, patches from `fix/` branches) |
| **Docker Tags** | `:edge`, `:X.Y.Z`, `:sha-<short-sha>` |
| **Environments** | Development (`edge`) + production (`X.Y.Z`); staging (`X.Y.Z`) planned |
| **Hot-fixes** | Short-lived `fix/` branch + PATCH tag, isolated per MINOR version |
| **CAB** | Mandatory before production; staging validation planned |

---

## Expected Outcomes

- Consistent flow from code → tag → deployment
- Faster environment promotion with fewer manual errors
- Reliable and traceable version history
- Simplified hot-fix process
- Transparent CAB-governed production releases
