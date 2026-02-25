# Improve Dependabot Configuration

## Context

The transitdata repositories currently have basic Dependabot configs (monthly schedule, `target-branch: develop`, no grouping, no cooldown, no Docker tracking). The goal is to reduce PR noise, gain supply-chain attack resilience via cooldown, and keep timely updates — applied consistently across all repos.

Default branch is `main` across all repos. Existing configs use `target-branch: "develop"` (gitflow pattern).

## Approach: Alternative 2 Grouping + Cooldown + Multi-Ecosystem

### Grouping Strategy

For the primary package ecosystem (maven/gradle/pip):
- **`dev-all`** group: all update types for development dependencies → one PR
- **`prod-minor-patch`** group: minor + patch for production dependencies → one PR
- **Major production deps**: ungrouped → individual PRs (require changelog review)

For infrastructure ecosystems (github-actions + docker):
- **`infrastructure`** group (multi-ecosystem): minor + patch updates for both github-actions and docker combined into a single PR
- **Major updates**: ungrouped → individual PRs

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

**Security updates are exempt from cooldown** because `target-branch: develop` is a non-default branch. Per the docs: cooldown does not affect security updates when `target-branch` points to a non-default branch.

### Other Settings

- `open-pull-requests-limit: 20` on all ecosystem entries
- `schedule.interval: "monthly"` — unchanged
- `target-branch: "develop"` — unchanged

## Template Configurations

### Maven repos

```yaml
version: 2
updates:
  - package-ecosystem: "maven"
    directory: "/"
    schedule:
      interval: "monthly"
    target-branch: "develop"
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
      interval: "monthly"
    target-branch: "develop"
    open-pull-requests-limit: 20
    cooldown:
      default-days: 30
      semver-major-days: 90
      semver-minor-days: 60
      semver-patch-days: 30
    groups:
      infrastructure:
        update-types:
          - "minor"
          - "patch"
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "monthly"
    target-branch: "develop"
    open-pull-requests-limit: 20
    cooldown:
      default-days: 30
      semver-major-days: 90
      semver-minor-days: 60
      semver-patch-days: 30
    groups:
      infrastructure:
        update-types:
          - "minor"
          - "patch"
```

The `infrastructure` group name shared between `docker` and `github-actions` enables multi-ecosystem grouping — their minor+patch updates are combined into a single PR.

### Gradle repos (e.g. transitlog-apc-sink, transitlog-hfp-csv-sink)

Same as Maven template but replace `"maven"` with `"gradle"`.

### Python repos (e.g. transitdata-monitor-data-collector)

Same structure but replace `"maven"` with `"pip"`.

### Shared-workflows repo (e.g. transitdata-shared-workflows)

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "monthly"
    open-pull-requests-limit: 20
    cooldown:
      default-days: 30
      semver-major-days: 90
      semver-minor-days: 60
      semver-patch-days: 30
    groups:
      infrastructure:
        update-types:
          - "minor"
          - "patch"
```

No `target-branch` (targets default `main`). No docker or package ecosystem entries.

## Changes

### Repos with existing dependabot.yml

Add grouping, cooldown, docker ecosystem, and bump PR limit to 20. Use the appropriate template (Maven, Gradle, or Python) based on the repo's primary ecosystem.

### Repos without dependabot.yml

Create a new `.github/dependabot.yml` using the appropriate template. Use `target-branch: "develop"` for service repos. For workflow-only repos (like transitdata-shared-workflows), omit `target-branch` so PRs target the default `main` branch.

### Skip

Repos that are purely documentation or deployment configs (no package dependencies) don't need Dependabot.