# Standardized Docker base images solution proposal

### A unified foundation for Team InfoDevOps microservices

---

## What?

Team InfoDevOps must own some official base images used by microservices maintained under [a single place](https://github.com/HSLdevcom/infodevops-docker-base-images).
These images provide:

- Language-specific standardization
- JDK/JRE images for Java / Kotlin
- Node-based images for Typescript
- Python runtime images for Python
- Security-patched OS layers, updated centrally and automatically
- Preconfigured Azure requirements
- Azure Functions tooling
- Logging and monitoring agents (if needed)
- Standard environment variables
- Performance and build optimizations
- Reduced image size
- Layer caching 
- Faster CI/CD pipelines 
- Predictable deployments

Same base Docker image leads to same behaviors across all environments:
- local development
- CI/CD pipelines
- Azure Functions
- Azure Kubernetes Service (AKS) workloads

---

## Why?

In a multi-repo organization with dozens of microservices written in multiple programming languages, such as:
Java, Kotlin, Typescript and Python, maintaining consistent, secure and predictable runtime environments becomes increasingly difficult.
Without standardization, each repository builds its own Docker image differently, which leads to:

- Security risks;
- Different images that lead to different vulnerabilities & inconsistent patching;
- Non-reproducible builds;
- Two services using the same language may behave differently due to variations in OS, dependencies, or base image tags;
- Slower development and onboarding
- Setup logic (JDK installation, Node versioning, Python deps, environment variables) is duplicated for each repo;
- Higher operational cost (eg: upgrading Java version for base image only instead of upgrading for each and every repo);
- Potential issues caused by differences in layers, unstable builds, and missing optimizations;
- Potential deployment inconsistencies across Azure;
- Whether running in Azure Kubernetes Service (AKS) or Azure Functions, non-standard images increase debugging complexity;

By introducing centralized, versioned Docker base images, Team InfoDevOps ensures that all services start from a secure, optimized and unified baseline.

---

## How?

### 1. Create standardized base Docker images

As the microservices maintained by Team InfoDevOps are developed by using multiple programming languages (i.e.: Java, Kotlin, Python, TypeScript),
it is required to create at least one standardized base Docker image per each programming language in use.

Each image is versioned and tagged to allow safe upgrades.

### 2. Use standardized Docker images

A microservice's Dockerfile should reuse the standard base Docker image as it follows:

```Dockerfile
FROM hsldevcom/base/java:11
# or
FROM hsldevcom/base/node:18
# or
FROM hsldevcom/base/python:3.11

```

### 3. Services inherit standardized best practices

Every container gets the same:
- Secure OS base
- Preconfigured runtime
- Recommended defaults (timezone, charset, memory flags, health scripts)
- Logging & monitoring conventions
- Azure deployment optimizations

This reduces debugging time and increases platform stability.

### 4. Consistent CI/CD workflows

Using the same base images across all repos makes pipelines:
- faster
- safer
- easier to maintain
- predictable across all environments

Combined with our [trunk-based development](Trunk-Based-Development-Migration-Plan-Proposal.md) strategy and [unified GitHub Actions workflows](CI-CD-Design-Proposal.md), 
this ensures a smooth release pipeline for all applications.
