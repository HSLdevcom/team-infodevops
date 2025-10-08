# One pager: CI/CD Design Proposal 

## What?
Currently, InfoDevOps team is owning and managing more than 100 repos, where each and every repo is running a separate CI/CD pipeline.
There is not any standard way of how the CI/CD pipelines are being shaped and executed.

InfoDevOps team identified that CI/CD pipelines are needed for all our repos for performing multiple tasks:
- _code formatting & linting_
- _validation checks (eg: running unit tests)_
- _integrating the code from feature branches into `dev` or `main` branches_
- _building Docker images (only for `dev` or `main`)_
- _publishing Docker images (only for `dev` or `main`)_

The CI/CD pipelines need to be implemented by using GitHub Actions as this is the in-use technology at this moment.

Also, it is mandatory to take in consideration the fact that there are used multiple programming languages and build tools combinations, such as:
- Java and Maven
- Kotlin and Gradle
- Typescript and NPM/Yarn
- Python and pip/pipx

## Why?
Since each and every repo that InfoDevOps team is owning and managing is maintaining a separate CI/CD, there is definitely
the need to standardize how all these pipelines are being shaped and are being executed.

As an example to demonstrate why the need of standardization exists, recently, there was an initiative to integrate code formatting into each and every project. The initiative was consumed by implementing
manual changes in every source-code repository and in each repo's CI/CD pipeline definitions.
This could have been implemented easier if some standard templates had been used for implementing the CI/CD pipelines.

Another example that can prove the usefulness of shared GitHub Actions templates is in case of increasing some programming language (eg: Java, node.js) version or some other build-tool related technology.
This can be done only in the templates and reuse them as needed, instead of changing each and ever pipeline definition.

By implementing a standard way that will be based on GitHub Actions shared templates that will be used subsequently to create specific CI/CD pipelines,
in a situation as the one described above, cross-functional aspects that can be implemented just at the template level, rather than changing all the CI/CD pipelines. 

## How?

As it was already mentioned, the standardization will be implemented by creating some shared GitHub Actions templates that can be subsequently used for existing 
projects and reused in case of new projects that will be developed from now on.

The templates will be covered as **two reusable workflows**:
- `ci.yml` -> triggered on PRs and pushes; runs up to Docker build (no push)
- `cd.yml` → triggered on `main`/`dev` branch merges or tags; handles image publish + deploy

### 1. Java + Maven
**Tools:** `mvn`, `spotless`, `JUnit`

**Pipeline stages:**

In `ci.yml` we will have the following stages:

#### 1.1. Setup
```
- uses: actions/checkout@v4

- uses: actions/setup-java@v4
  with:
  distribution: 'temurin'
  java-version: '21'

```

#### 1.2. Check code formatting & linting
```
- name: Check code format and lint
  run: |
  mvn spotless:check
```

#### 1.3. Run tests
```
- name: Run tests
  run: mvn test
```

#### 1.4. Build artifact
```
- name: Build artifact
  run: mvn package -DskipTests
```

#### 1.5. Build Docker Image
```
- name: Build Docker image
  run: docker build -t ghcr.io/org/myservice:${{ github.sha }} .
```

In `cd.yml`, that will run only on `main` or `dev` branches,  we will have the following stages:

#### 1.6. Push Docker image
```
- name: Push Docker image
  if: github.ref == 'refs/heads/main' || github.ref == 'refs/heads/develop'
  run: docker push ghcr.io/org/myservice:${{ github.sha }}
```

### 2. Kotlin + Gradle

#### 2.1. Setup
```
- uses: actions/checkout@v4
- name: Set up JDK 11
uses: actions/setup-java@v4
with:
  distribution: 'temurin'
  java-version: '11'
  cache: 'gradle'
```

#### 2.2. Check code formatting & linting
```
- name: Run Spotless Apply
  run: ./gradlew spotlessApply
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

#### 2.3. Run tests
```
- name: Run tests
  run: ./gradlew test
```

#### 2.4. Build artifact
```
- name: Build artifact
  run: ./gradlew build -x test
```

#### 2.5. Build Docker Image
```
- name: Build Docker image
  run: docker build -t ghcr.io/org/myservice:${{ github.sha }} .
```

In `cd.yml`, that will run only on `main` or `dev` branches,  we will have the following stages:

#### 2.6. Push Docker image
```
- name: Push Docker image
  if: github.ref == 'refs/heads/main' || github.ref == 'refs/heads/develop'
  run: docker push ghcr.io/org/myservice:${{ github.sha }}
```

### 3. TypeScript (Node.js/Yarn)

#### 3.1. Setup
```
- name: Checkout
  uses: actions/checkout@v4

- name: Install Node
  uses: actions/setup-node@v4
  with:
    node-version: "lts/*"
    cache: "npm"

- name: Install NPM dependencies
  run: yarn install --frozen-lockfile

```

#### 3.2. Check code formatting & linting
```
- name: Check code formatting
  run: npm run format:check
```

#### 3.3. Run tests
```
- name: Run tests
  run: npm test -- --coverage
```

#### 3.4. Build artifact
```
- name: Build app
  run: npm run build
```

#### 3.5. Build Docker Image
```
- name: Build Docker image
  run: docker build -t ghcr.io/org/myservice:${{ github.sha }} .
```

In `cd.yml`, that will run only on `main` or `dev` branches,  we will have the following stages:

#### 3.6. Push Docker image
```
- name: Push Docker image
  if: github.ref == 'refs/heads/main' || github.ref == 'refs/heads/develop'
  run: docker push ghcr.io/org/myservice:${{ github.sha }}
```

### 4. Python

#### 4.1. Setup
```
- uses: actions/checkout@v4

- uses: actions/setup-python@v5
  with:
    python-version: '3.11'

- name: Install dependencies
  run: pip install
```

#### 4.2. Check code formatting & linting
```
- name: Check code formatting
  run: |
    ruff check .
    ruff format --check
```

#### 4.3. Run tests
```
- name: Run tests
  run: pytest --junitxml=test-results.xml
```

#### 4.4. Build artifact
```
- name: (Optional) Build package
  run: python -m build
```

#### 4.5. Build Docker Image
```
- name: Build Docker image
  run: docker build -t ghcr.io/org/myservice:${{ github.sha }} .
```

In `cd.yml`, that will run only on `main` or `dev` branches,  we will have the following stages:

#### 4.6. Push Docker image
```
- name: Push Docker image
  if: github.ref == 'refs/heads/main' || github.ref == 'refs/heads/develop'
  run: docker push ghcr.io/org/myservice:${{ github.sha }}
```

The reusable workflows will be centralized in `./github/workflows` within a shared repo, i.e. `transitdata-workflows-templates`.
There might be multiple templates per each combination of programming language and build tool (eg: `ci-java-maven.yml`, `ci-kotlin-gradle.yml`, `ci-node.yml`, etc.)
Afterward, in each microservice repo, the templates might be referenced as it follows:

```
name: CI

on:
  pull_request:
  push:
    branches: [ main, develop ]

jobs:
  call-ci:
    uses: HSL/transitdata-workflows-templates/.github/workflows/ci-node.yml@main
    with:
      docker-image-name: myservice
    secrets: inherit
```

_**Some considerations that can be discussed for deployments only:**_
- Only trigger on merges to `main`, `dev`, `develop`, or tags (needs to be decided)
- After pushing the Docker image, optionally:
  - Update a Helm values file in a deployment repo and create a PR, or
  - Trigger GitOps (eg: ArgoCD, FluxCD) sync
  - Run `kubectl` commands to execute deployment



