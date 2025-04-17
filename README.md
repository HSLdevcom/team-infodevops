# Team InfoDevOps

Our team InfoDevOps develops and maintains several services related to passenger information. This repository acts as the starting point for documentation about the practices and the services of our team.

By default we publish the information but some information we must hide for security and privacy reasons.
Then we link to the documentation stored elsewhere.

## Team practices

- Onboarding
  - Accounts and authorization
  - Domain knowledge basics
- Development process
  - Version control
    - Branching
  - Testing
  - Observability
    - Metrics
    - Logs
    - Traces
    - Alerts
  - Documentation
    - Templates
  - Environments
  - Deployment process
  - CI/CD
    - Templates
  - Naming
  - Creating new repositories, projects and services
  - Responsibilities
    - Responsiveness to fires, on-call etc.
    - Boundaries and contact points to other teams (no names or contact details)
    - SLOs, SLAs of our input and our output
  - Support structures
    - Communication practices
      - What is done async/sync?
      - Document here, not in chat
    - Describe the minimal process needed, e.g. recurring meetings

## Services

### Transitdata

Transitdata collects, processes, stores and publishes streaming ("realtime") passenger information.
That includes for example:

- vehicle positions and status messages
- stop arrival and departure time predictions
- textual service alerts
- journey cancellations
- automatic passenger counting

Transitdata does not provide user interfaces and can be thought of as the crucial data plumbing to enable other services.

More information in the [Transitdata documentation repository](https://github.com/HSLdevcom/transitdata).

### Transitlog

[Transitlog](https://reittiloki.hsl.fi/) ("Reittiloki" in Finnish) stores and visualizes historical information from the vehicles in detail with a latency of seconds.

Transitlog is used by the staff of HSL, by the public transport operators and sometimes by customers.
Transitlog gets its data from Transitdata.

More information in the [Transitlog documentation repository](https://github.com/HSLdevcom/transitlog).

### Maps and some printed materials

Services related to maps and printing and managing materials, posters and signs at stops.

### hfp-analytics

Data analysis based on High-frequency positioning (HFP).

### helmet-ui

A UI for the HELMET model built with EMME.

### jore-map-ui

A map interface for Jore3.
