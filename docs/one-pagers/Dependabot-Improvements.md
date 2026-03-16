# Improve Dependabot Configuration

## Context

The transitdata repositories currently have basic Dependabot configs (monthly schedule, no grouping, no cooldown, no Docker tracking). The goal is to reduce PR noise, gain supply-chain attack resilience via cooldown, and keep timely updates — applied consistently across all repos.

Default branch is `main` across all repos. Dependabot targets the default branch by default, so no `target-branch` override is needed.

## Approach: Alternative 2 Grouping + Cooldown + Multi-Ecosystem

### Grouping Strategy

For the primary package ecosystem (maven/gradle/pip):
- **`dev-all`** group: all update types for development dependencies → one PR
- **`prod-minor-patch`** group: minor + patch for production dependencies → one PR
- **Major production deps**: ungrouped → individual PRs (require changelog review)

For infrastructure ecosystems (github-actions + docker):
- **`hsldevcom-infra`** group (multi-ecosystem): all updates for HSLdevcom-originating docker and github-actions packages combined into a single PR, using `patterns` to match only `hsldevcom/*` / `HSLdevcom/*` packages
- **Non-HSLdevcom packages**: grouped per-ecosystem for minor+patch, with majors ungrouped → individual PRs

### Cooldown

Applied to all ecosystems:
```yaml
cooldown:
  default-days: 30
  semver-major-days: 90
  semver-minor-days: 60
  semver-patch-days: 30
```

`default-days: 30` serves as fallback for packages that don't follow semver (e.g., some Docker images).

**Security updates bypass cooldown** on the default branch. Per [GitHub docs](https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file#cooldown), cooldown does not delay security updates when PRs target the default branch.

### Other Settings

- `open-pull-requests-limit: 20` on all ecosystem entries
- `schedule.interval: "daily"` — with auto-merge enabled, no extra delay is needed on top of cooldown

## Template Configuration

A single unified template is used for all repos. Dependabot ignores ecosystems that don't apply to a given repo, so one template everywhere simplifies centralized management.

```yaml
version: 2
multi-ecosystem-groups:
  hsldevcom-infra:
    schedule:
      interval: "daily"
    updates:
      - package-ecosystem: "docker"
        directory: "/"
        patterns: ["hsldevcom/*"]
        multi-ecosystem-group: "hsldevcom-infra"
      - package-ecosystem: "github-actions"
        directory: "/"
        patterns: ["HSLdevcom/*"]
        multi-ecosystem-group: "hsldevcom-infra"
updates:
  - package-ecosystem: "maven"
    directory: "/"
    schedule:
      interval: "daily"
    open-pull-requests-limit: 20
    cooldown:
      default-days: 30
      semver-major-days: 90
      semver-minor-days: 60
      semver-patch-days: 30
    groups:
      dev-all:
        dependency-type: "development"
        update-types:
          - "major"
          - "minor"
          - "patch"
      prod-minor-patch:
        dependency-type: "production"
        update-types:
          - "minor"
          - "patch"
  - package-ecosystem: "gradle"
    directory: "/"
    schedule:
      interval: "daily"
    open-pull-requests-limit: 20
    cooldown:
      default-days: 30
      semver-major-days: 90
      semver-minor-days: 60
      semver-patch-days: 30
    groups:
      dev-all:
        dependency-type: "development"
        update-types:
          - "major"
          - "minor"
          - "patch"
      prod-minor-patch:
        dependency-type: "production"
        update-types:
          - "minor"
          - "patch"
  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "daily"
    open-pull-requests-limit: 20
    cooldown:
      default-days: 30
      semver-major-days: 90
      semver-minor-days: 60
      semver-patch-days: 30
    groups:
      dev-all:
        dependency-type: "development"
        update-types:
          - "major"
          - "minor"
          - "patch"
      prod-minor-patch:
        dependency-type: "production"
        update-types:
          - "minor"
          - "patch"
  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "daily"
    open-pull-requests-limit: 20
    cooldown:
      default-days: 30
      semver-major-days: 90
      semver-minor-days: 60
      semver-patch-days: 30
    groups:
      docker-minor-patch:
        update-types:
          - "minor"
          - "patch"
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "daily"
    open-pull-requests-limit: 20
    cooldown:
      default-days: 30
      semver-major-days: 90
      semver-minor-days: 60
      semver-patch-days: 30
    groups:
      actions-minor-patch:
        update-types:
          - "minor"
          - "patch"
```

The `multi-ecosystem-groups` block groups HSLdevcom-originating docker and github-actions updates into a single PR, since new shared Dockerfile and shared workflow versions are often related. Non-HSLdevcom docker and github-actions updates are handled by their respective per-ecosystem groups (`docker-minor-patch`, `actions-minor-patch`) for minor+patch, with majors ungrouped as individual PRs.

## Changes

### Repos with existing dependabot.yml

Overwrite with the unified template above. This replaces any existing grouping, schedule, and ecosystem configuration.

### Repos without dependabot.yml

Create a new `.github/dependabot.yml` using the unified template above.

### Skip

Repos that are purely documentation or deployment configs (no package dependencies) don't need Dependabot.
