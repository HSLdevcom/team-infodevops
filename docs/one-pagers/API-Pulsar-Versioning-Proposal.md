# One Pager: Design Proposal for API and Pulsar Topic Versioning

> **Status:** Draft — extracted from the [Branching, Versioning, and Deployment Proposal](./Branching-Versioning-Deployment-Proposal.md) for separate discussion.

## What?

This proposal defines a standard approach for versioning:

- Public and partner-facing APIs
- HSL-internal APIs
- Team-internal APIs
- Pulsar topics and message schemas

---

## Why?

As the number of services and integration points grows, inconsistent versioning leads to:

- Breaking changes discovered too late by consumers
- Unclear contracts between teams and external partners
- Difficulty evolving message schemas without downtime

A consistent versioning approach ensures predictable evolution and safe rollout of changes across all integration points.

---

## How?

### 1. Versioning: Public/Partner APIs

- Versioned through **URL prefixing**: `/api/v1/...`
- Increment MAJOR version (`/v2/`) when breaking changes occur.
- Deprecated versions remain accessible for a transition period.

Example:
```
/api/v1/users
/api/v2/users
```

---

### 2. Versioning: HSL-internal APIs

- Internal APIs use the same SemVer approach but are coordinated via internal dependency management.
- Changes are reflected in OpenAPI definitions.
- Breaking changes → MAJOR version increment in `/internal/vX/` path.

Example:
```
/internal/v1/vehicle-status
```

---

### 3. Versioning: Team-internal APIs

- For intra-team development, explicit versioning may be skipped during early iteration.
- Optional `/dev/` endpoint can be used to indicate unstable contracts.
- Once stabilized, versioning follows the standard `/v1/` scheme.

Example:
```
/dev/metrics
/v1/metrics
```

---

### 4. Versioning: Pulsar Topics

To support schema evolution in event-driven systems:

- Add version suffix to topic names: `topic.v1`, `topic.v2`
- Increment version when schema or serialization changes are not backward compatible.
- Schema changes follow **SchemaVer** (`MAJOR-MINOR-PATCH`) for consistency with JSON schema management.

Example:
```
vehicle.events.v1
vehicle.events.v2
```

---

## Summary

| Aspect | Decision |
|--------|-----------|
| **Public/Partner APIs** | `/api/v1/`, `/api/v2/` URL prefixing |
| **HSL-internal APIs** | `/internal/v1/` with OpenAPI definitions |
| **Team-internal APIs** | Optional `/dev/` during iteration, `/v1/` once stable |
| **Pulsar Topics** | `topic.v1`, `topic.v2` using SchemaVer |

---

## Open Questions

- How long are deprecated API versions maintained? What is the sunset policy?
- How do API version changes relate to the SemVer scheme of the service?
- How does the Pulsar schema registry integrate with topic versioning?
- How do consumers and producers coordinate version transitions?
