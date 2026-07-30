# One Pager: Microservice Modernization Checklist

## What?

HSL InfoDevOps manages 100+ microservices across multiple repos. These services were built
independently and have accumulated inconsistencies in build tooling, CI/CD pipelines,
Dockerfiles, Java/Node versions, and branch strategies.

A set of shared standards has been established covering:
- Shared reusable GitHub Actions workflows (`transitdata-shared-workflows`)
- Standardized Docker base images (`infodevops-docker-base-images`)
- Unified Dependabot configuration and auto-approve policy
- Trunk-based development with a single `main` branch
- Semantic versioning with Docker tags (`:edge`, `:X.Y.Z`, `:sha-<hash>`)

As of 2026-03, approximately 8 of 34 services have been migrated. The remaining ~26 services
need to be brought up to this standard. This one-pager describes what needs to change, why
it matters, and provides a per-ecosystem checklist to guide developers through the migration.

---

## Why?

### Old pattern (pre-migration)
| Area | Old state |
|---|---|
| Workflow file | `test-and-build.yml` — inline, per-repo pipeline |
| CI trigger | All branches/tags, no structured release flow |
| Java version | 11 (eclipse-temurin:11-alpine) |
| Dockerfile | Single-stage, `eclipse-temurin:11-alpine`, pre-built jar copied in |
| Docker registry secrets | `TRANSITDATA_DOCKERHUB_USER` / `TRANSITDATA_DOCKERHUB_TOKEN` |
| Spotless | `spotless:apply` (auto-fixes and commits reformatted code in CI) |
| Test location | Outside Docker, on runner |
| Branch strategy | `aks-dev` / `develop` / `master` long-lived branches |
| Docker tag in dev K8s | `aks-dev` or `develop` |
| Dependabot | Missing, minimal, or not unified |
| Dependabot auto-approve | Missing |

### New standard (post-migration)
| Area | New state |
|---|---|
| Workflow file | `ci-cd.yml` — thin caller that delegates to shared workflow |
| CI trigger | PRs and pushes; Docker publish only on `main` and version tags |
| Java version | 25 (LTS) |
| Dockerfile | Two-stage: `hsldevcom/infodevops-docker-base-images:*-25-java-jdk` build + `*-25-java-jre` runtime |
| Docker registry secrets | `DOCKER_HUB_INFODEVOPS_USERNAME` / `DOCKER_HUB_INFODEVOPS_TOKEN` |
| Spotless | `spotless:check` (fails pipeline on formatting issues, never auto-commits) |
| Test location | Inside Docker (`runTestsInsideDocker: true`) catching JVM runtime mismatches |
| Branch strategy | `main` only; short-lived `feat/`, `fix/`, `refactor/` branches (trunk-based) |
| Docker tag in dev K8s | `edge` (rolling tag tracking latest `main`) |
| Dependabot | Unified template: daily schedule, grouped PRs, 30/60/90-day cooldown |
| Dependabot auto-approve | `dependabot-auto-approve.yml` — auto-approves patch/minor, flags major prod deps |

**Why these changes matter:**
- Running tests inside Docker catches cases where code compiles on Java 11 (runner) but the
  container runs Java 25 — a class of bug that silently passes CI but fails in production.
- Centralizing the pipeline in shared workflows means runtime or tool upgrades happen in one
  place and propagate to all services.
- `spotless:check` vs `spotless:apply` avoids CI commits altering code under review in PRs.
- The `edge` tag in K8s dev manifests always reflects the latest `main`, eliminating the need
  to manually update image tags after every merge.
- Dependabot cooldown prevents supply-chain attacks where a malicious package version is
  published and immediately pulled in. Security updates bypass cooldown automatically.

---

## How?

The steps below assume the developer has the repository checked out locally and has
access to the HSLdevcom GitHub organization.

> **Prerequisite for all ecosystems:** Before running `spotless:check`, run
> `spotless:apply` locally one final time to ensure the codebase is formatted. Commit
> the result. After this, CI will only *check* formatting and never auto-fix.

---

### Java + Maven

#### 1. Branch hygiene (trunk-based development)
- [ ] Create `main` branch if it does not exist. Source it from the branch that has the
      latest production-ready work (typically `aks-dev`).
- [ ] `git diff aks-dev main` (and `master`, `develop` if they exist) — cherry-pick or
      merge any commits in those branches that are not yet in `main`.
- [ ] Set `main` as the default branch in GitHub repository settings.
- [ ] Delete or archive stale long-lived branches (`aks-dev`, `develop`, `master`) once
      their work is merged into `main`.

#### 2. Upgrade Java version to 25
- [ ] In `pom.xml`, update `<java.version>` (or `<maven.compiler.source>` /
      `<maven.compiler.target>`) from `11` to `25`:
  ```xml
  <properties>
      <java.version>25</java.version>
      ...
      <maven.compiler.release>${java.version}</maven.compiler.release>
  </properties>
  ```
  Replace the old `source`/`target` pair with a single `release` property — `release`
  enforces both compile compatibility and API availability, `source`/`target` does not.
- [ ] Run `./mvnw compile` locally on Java 25 to catch any API incompatibilities.
- [ ] Fix any compilation errors from removed or changed APIs (e.g., deprecated `finalize`,
      removed Nashorn, changed reflection access).

#### 3. Replace Dockerfile with two-stage standard pattern
- [ ] Replace the entire `Dockerfile` content with the standard two-stage pattern:
  ```dockerfile
  # syntax=docker/dockerfile:1
  # check=error=true

  FROM hsldevcom/infodevops-docker-base-images:1.0.2-25-java-jdk AS build
  WORKDIR /usr/app
  ARG GITHUB_ACTOR=github-actions
  COPY mvnw pom.xml ./
  COPY .mvn .mvn
  COPY .mvn/settings.xml /root/.m2/settings.xml
  COPY src src
  RUN --mount=type=secret,id=github_token \
      export GITHUB_TOKEN="$(cat /run/secrets/github_token)" && \
      export GITHUB_ACTOR="$GITHUB_ACTOR" && \
      ./mvnw -B package -DskipTests

  FROM hsldevcom/infodevops-docker-base-images:1.0.2-25-java-jre
  COPY --from=build /usr/app/target/<service-name>.jar /usr/app/<service-name>.jar
  ENTRYPOINT ["java", "-XX:InitialRAMPercentage=10.0", "-XX:MaxRAMPercentage=95.0", "-jar", "/usr/app/<service-name>.jar"]
  ```
  Replace `<service-name>` with the actual jar name (check `pom.xml`
  `<finalName>` or `maven-assembly-plugin` descriptor).
- [ ] Verify the Maven wrapper (`mvnw` + `.mvn/` directory) is committed to the repo. If
      missing, generate it: `mvn wrapper:wrapper`.
- [ ] Confirm `.mvn/settings.xml` exists and contains the GitHub Packages repository
      entry (needed to resolve `transitdata-common` and other HSL dependencies).
- [ ] Remove the old `start-application.sh` script if the service uses one — the new
      pattern uses `ENTRYPOINT` directly.
- [ ] Remove the old single-stage `FROM eclipse-temurin:11-alpine` line and any
      `RUN apk add --no-cache curl` lines (curl is included in the base images).
- [ ] Build the image locally to verify: `docker build --secret id=github_token,env=GITHUB_TOKEN .`

#### 4. Replace CI/CD workflow
- [ ] Delete `.github/workflows/test-and-build.yml`.
- [ ] Create `.github/workflows/ci-cd.yml`:
  ```yaml
  name: CI/CD

  on:
    push:
      branches:
        - main
      tags:
        - "v*"
    pull_request:
    merge_group:

  jobs:
    build:
      uses: HSLdevcom/transitdata-shared-workflows/.github/workflows/ci-cd-java.yml@1.0.5
      secrets: inherit
      with:
        runTestsInsideDocker: true
  ```
  Check `transitdata-shared-workflows` for the latest `@<version>` tag to pin to.
- [ ] Remove any inline CodeQL or dependency-scan workflows that duplicate what the shared
      workflow already handles.

#### 5. Format code and switch to check-only
- [ ] Run `./mvnw spotless:apply` locally to reformat all code.
- [ ] Commit the formatting changes separately (e.g., `style: apply spotless formatting`).
- [ ] Verify `./mvnw spotless:check` passes cleanly. From this point, CI runs `check` only.

#### 6. Separate unit and integration tests
- [ ] Confirm that unit test classes follow the `*Test.java` naming convention and
      integration test classes follow `*IT.java`.
- [ ] Run `./mvnw test` (unit tests only) to verify all unit tests pass inside Docker.
      The shared workflow uses `mvn test` inside Docker and `mvn verify` for integration
      tests (using Testcontainers) outside Docker.
- [ ] If any test uses Docker-in-Docker (Testcontainers), annotate it with `*IT.java`
      so it is excluded from the Docker-internal test run.

#### 7. Dependabot configuration
- [ ] Create or overwrite `.github/dependabot.yml` with the unified template from
      [`Dependabot-Improvements.md`](./Dependabot-Improvements.md).
      Use only the `maven`, `docker`, and `github-actions` ecosystems for Java services;
      Dependabot silently ignores ecosystems that don't apply.
- [ ] Create `.github/workflows/dependabot-auto-approve.yml` (copy from
      `transitdata-partial-apc-expander-combiner` as reference).

#### 8. Update AKS deploy manifest
- [ ] In the corresponding manifest in `transitdata-aks-deploy/manifests/<service>.yaml`,
      update the dev environment image tag from `aks-dev` (or `develop`) to `edge`:
  ```yaml
  image: hsldevcom/<service-name>:edge
  ```

#### 9. Verify and open PR
- [ ] Run the full CI pipeline locally: `./mvnw spotless:check test package`.
- [ ] Build Docker image locally and run it to confirm the service starts correctly.
- [ ] Open a pull request to `main`. Ensure the `ci-cd.yml` workflow passes in full
      (spotless check, unit tests inside Docker, Docker build).

---

### Kotlin + Gradle

#### 1. Branch hygiene (trunk-based development)
- [ ] Same steps as Java §1 above — create `main` from latest work, merge stale branches,
      set `main` as default, delete stale branches.

#### 2. Upgrade JVM version to 25
- [ ] In `build.gradle.kts` (or `build.gradle`), update `jvmToolchain` / `jvmTarget`:
  ```kotlin
  kotlin {
      jvmToolchain(25)
  }
  tasks.withType<KotlinCompile> {
      kotlinOptions.jvmTarget = "25"
  }
  ```
- [ ] Update the Gradle wrapper if it is outdated: `./gradlew wrapper --gradle-version <latest>`.
- [ ] Run `./gradlew build` locally on Java 25 to confirm no API breakage.

#### 3. Replace Dockerfile with two-stage standard pattern
- [ ] Replace `Dockerfile` with the Kotlin/Gradle two-stage pattern:
  ```dockerfile
  # syntax=docker/dockerfile:1
  # check=error=true

  FROM hsldevcom/infodevops-docker-base-images:1.0.2-25-java-jdk AS build
  WORKDIR /usr/app
  ARG GITHUB_ACTOR=github-actions
  COPY gradlew build.gradle.kts settings.gradle.kts ./
  COPY gradle gradle
  COPY src src
  RUN --mount=type=secret,id=github_token \
      export GITHUB_TOKEN="$(cat /run/secrets/github_token)" && \
      export GITHUB_ACTOR="$GITHUB_ACTOR" && \
      ./gradlew shadowJar --no-daemon

  FROM hsldevcom/infodevops-docker-base-images:1.0.2-25-java-jre
  COPY --from=build /usr/app/build/libs/<service-name>.jar /usr/app/<service-name>.jar
  ENTRYPOINT ["java", "-XX:InitialRAMPercentage=10.0", "-XX:MaxRAMPercentage=95.0", "-jar", "/usr/app/<service-name>.jar"]
  ```
- [ ] Verify `.mvn/settings.xml` equivalent — for Gradle, confirm `~/.gradle/gradle.properties`
      or `gradle/gradle.properties` passes `GITHUB_TOKEN`/`GITHUB_ACTOR` for resolving HSL packages.
- [ ] Remove `start-application.sh` and old single-stage FROM line.

#### 4. Replace CI/CD workflow
- [ ] Delete `.github/workflows/test-and-build.yml`.
- [ ] Create `.github/workflows/ci-cd.yml`:
  ```yaml
  name: CI/CD

  on:
    push:
      branches:
        - main
      tags:
        - "v*"
    pull_request:
    merge_group:

  jobs:
    build:
      uses: HSLdevcom/transitdata-shared-workflows/.github/workflows/ci-cd-kotlin.yml@1.0.5
      secrets: inherit
      with:
        runTestsInsideDocker: true
  ```

#### 5. Format code and switch to check-only
- [ ] Run `./gradlew spotlessApply` locally and commit the result.
- [ ] Verify `./gradlew spotlessCheck` passes. From this point, CI runs `spotlessCheck` only.

#### 6. Separate unit and integration tests
- [ ] Ensure unit tests can run without Docker (no Testcontainers in `src/test/`).
- [ ] Move Docker-dependent tests to a separate `integrationTest` source set so the shared
      workflow can run unit tests inside Docker and integration tests outside.
- [ ] Validate: `./gradlew test` passes without Docker daemon access.

#### 7. Dependabot configuration
- [ ] Create or overwrite `.github/dependabot.yml` using the unified template from
      [`Dependabot-Improvements.md`](./Dependabot-Improvements.md).
      Use `gradle`, `docker`, and `github-actions` ecosystems.
- [ ] Create `.github/workflows/dependabot-auto-approve.yml` (copy from reference).

#### 8. Update AKS deploy manifest
- [ ] Update the dev manifest image tag to `edge` (same as Java §8).

#### 9. Verify and open PR
- [ ] Run `./gradlew spotlessCheck test shadowJar` locally.
- [ ] Build and test Docker image locally.
- [ ] Open PR to `main`; confirm shared workflow passes.

---

### TypeScript + npm

#### 1. Branch hygiene (trunk-based development)
- [ ] Same steps as Java §1 above.

#### 2. Upgrade Node.js to LTS
- [ ] In `Dockerfile`, replace any hardcoded `node:16` / `node:18` base image references
      with the standardized HSL base image (Node 22 slim):
  ```dockerfile
  FROM hsldevcom/infodevops-docker-base-images:<ver>-node AS build
  ```
  Check `infodevops-docker-base-images` for the current node image tag.
- [ ] In `.github/workflows`, remove any `actions/setup-node` with hardcoded versions;
      the shared workflow uses `node-version: "lts/*"`.
- [ ] Update `engines` in `package.json` if set. The shared workflow pins
      `node-version: "lts/*"`, which currently resolves to **Node 24** (LTS advances
      over time). Set the minimum to match the current LTS, not the previous one:
  ```json
  "engines": { "node": ">=24" }
  ```
- [ ] Regenerate `package-lock.json` with the same Node version the shared workflow
      uses. A lockfile written by Node 22 is incompatible with `npm ci` on Node 24 and
      will cause CI failures even when local builds pass:
  ```sh
  # switch to the current LTS before regenerating
  node --version   # confirm you are on Node 24+
  rm package-lock.json
  npm install
  git add package-lock.json
  ```
- [ ] Run `npm ci && npm run build` locally with Node LTS (24) to verify no
      incompatibilities.

#### 3. Replace Dockerfile with two-stage standard pattern
- [ ] Migrate to a multi-stage Dockerfile that separates build, test, and runtime. The
      shared workflow targets the stage names `tester` (for `checkAndTestInsideDocker`)
      and `production` (for the final image) by name — these names are required:
  ```dockerfile
  # syntax=docker/dockerfile:1
  # check=error=true

  FROM hsldevcom/infodevops-docker-base-images:<ver>-node AS build
  WORKDIR /usr/app
  COPY package.json package-lock.json ./
  RUN npm ci
  COPY . .
  RUN npm run build

  FROM build AS tester
  RUN npm test

  FROM hsldevcom/infodevops-docker-base-images:<ver>-node AS production
  WORKDIR /usr/app
  COPY --from=build /usr/app/dist ./dist
  COPY --from=build /usr/app/node_modules ./node_modules
  COPY package.json ./
  ENTRYPOINT ["node", "dist/index.js"]
  ```
  Adjust `dist/index.js` to match the project's actual build output entry point.
- [ ] Add / update `.dockerignore` to default-deny and allowlist only what is needed:
  ```
  *
  !src
  !package.json
  !package-lock.json
  !tsconfig*.json
  ```

#### 4. Migrate from Yarn to npm (if applicable)
- [ ] The shared `ci-cd-typescript.yml` workflow uses `npm ci`. If the project uses Yarn,
      either migrate to npm (preferred for consistency) or confirm the shared workflow
      supports Yarn via the `checkAndTestOutsideDocker` input and a custom `check-and-build`
      npm script.
- [ ] If migrating to npm: delete `yarn.lock`, run `npm install`, commit `package-lock.json`.

#### 5. Add `check-and-build` npm script
- [ ] The shared workflow calls `npm run check-and-build` when
      `checkAndTestOutsideDocker: true`. Add this script to `package.json` if missing:
  ```json
  "scripts": {
      "check-and-build": "npm run lint && npm run format:check && npm test && npm run build"
  }
  ```
  Adjust to match the project's existing lint/format/test script names.

#### 6. Replace CI/CD workflow
- [ ] Delete existing workflow files (e.g., `test-and-build.yml`, `buildAndPublish_prod.yml`,
      inline `dev.yml` / `production.yml`).
- [ ] Create `.github/workflows/ci-cd.yml`:
  ```yaml
  name: CI/CD

  on:
    push:
      branches:
        - main
      tags:
        - "v*"
    pull_request:
    merge_group:

  jobs:
    build-check-test-push:
      uses: HSLdevcom/transitdata-shared-workflows/.github/workflows/ci-cd-typescript.yml@1.0.5
      secrets: inherit
      with:
        checkAndTestOutsideDocker: true
        checkAndTestInsideDocker: true
  ```
  Set `checkAndTestOutsideDocker: false` if the project has no outside-Docker test stage.

#### 7. Format code
- [ ] Run `npm run format` (or `prettier --write .`) locally and commit.
- [ ] Verify `npm run format:check` (or `prettier --check .`) passes.

#### 8. Separate unit and integration tests
- [ ] Confirm `npm test` (unit tests) can run without a running database or external services.
- [ ] If integration tests require external services, gate them behind a separate npm script
      (e.g., `npm run test:integration`) that is not called during the Docker-internal run.

#### 9. Dependabot configuration
- [ ] Create or overwrite `.github/dependabot.yml` using the unified template from
      [`Dependabot-Improvements.md`](./Dependabot-Improvements.md).
      Use `npm`, `docker`, and `github-actions` ecosystems.
- [ ] Create `.github/workflows/dependabot-auto-approve.yml` (copy from reference).

#### 10. Update AKS deploy manifest
- [ ] Update the dev manifest image tag from `develop` / `aks-dev` to `edge`.

#### 11. Verify and open PR
- [ ] Run `npm run check-and-build` locally.
- [ ] Build and test Docker image locally.
- [ ] Open PR to `main`; confirm shared workflow passes.

---

## Reference: Already Migrated Services

The services below have completed the migration and can be used as reference implementations.

| Service | Ecosystem | Reference files |
|---|---|---|
| `transitdata-hfp-deduplicator` | Java + Maven | `Dockerfile`, `.github/workflows/ci-cd.yml` |
| `mqtt-pulsar-gateway` | Java + Maven | `Dockerfile`, `.github/workflows/ci-cd.yml` |
| `transitdata-metro-ats-parser` | Java + Maven | `.github/workflows/ci-cd.yml` (with `runTestsInsideDocker: true`) |
| `transitdata-partial-apc-expander-combiner` | TypeScript + npm | `Dockerfile`, `.github/workflows/ci-cd.yml`, `dependabot-auto-approve.yml` |

> Kotlin/Gradle: `transitdata-eke-sink` uses the old workflow and is pending migration —
> consult the shared `ci-cd-kotlin.yml` in `transitdata-shared-workflows` as the template.

---

## Quick Diff: Old vs New (Java summary)

```
# Workflow
-.github/workflows/test-and-build.yml (inline, JDK 11, spotless:apply, elgohr action)
+.github/workflows/ci-cd.yml         (delegates to shared workflow, runTestsInsideDocker: true)

# Dockerfile
-FROM eclipse-temurin:11-alpine
-RUN apk add --no-cache curl
-ADD target/<svc>-jar-with-dependencies.jar /usr/app/<svc>.jar
-COPY start-application.sh /
-CMD ["/start-application.sh"]

+FROM hsldevcom/infodevops-docker-base-images:1.0.2-25-java-jdk AS build
+  ... (maven wrapper build)
+FROM hsldevcom/infodevops-docker-base-images:1.0.2-25-java-jre
+COPY --from=build ... /usr/app/<svc>.jar
+ENTRYPOINT ["java", "-XX:InitialRAMPercentage=10.0", "-XX:MaxRAMPercentage=95.0", "-jar", ...]

# pom.xml
-<maven.compiler.source>11</maven.compiler.source>
-<maven.compiler.target>11</maven.compiler.target>
+<java.version>25</java.version>
+<maven.compiler.release>${java.version}</maven.compiler.release>

# K8s manifest (dev)
-image: hsldevcom/<service>:aks-dev
+image: hsldevcom/<service>:edge

# Secrets (no change in files, change in GitHub repo settings)
-TRANSITDATA_DOCKERHUB_USER / TRANSITDATA_DOCKERHUB_TOKEN
+DOCKER_HUB_INFODEVOPS_USERNAME / DOCKER_HUB_INFODEVOPS_TOKEN
```
