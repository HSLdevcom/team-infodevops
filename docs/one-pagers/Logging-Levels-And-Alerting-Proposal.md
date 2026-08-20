# Log level principles and alerting proposal

### Deciding what becomes a log line, what becomes a metric, and what wakes someone up

---

## What?

This proposal defines, for every microservice maintained by Team InfoDevOps:

- **The decision rule** for whether an event belongs in a log line, in a metric, or nowhere at all
- **The meaning of each log level** — `ERROR`, `WARN`, `INFO`, `DEBUG`, `TRACE` — expressed as a volume budget and an operational contract, not as a vague severity feeling
- **The alerting behaviour attached to each level**, so that a level choice is a deliberate decision about who gets woken up
- **Which environments collect which levels**, and at which retention tier
- **The writing rules** that make a log line useful to the person reading it at 03:00

Out of scope, deferred to follow-up proposals: the concrete Prometheus/Grafana deployment topology, dashboard design, distributed tracing, and the alert-routing rota.

---

## Why?

### 1. Logging is a direct, recurring cost

Log volume is billed. Azure Monitor Analytics Logs is roughly **five times the cost** of Basic Logs, and the minimum interactive retention period is **30 days** — so long-term retention options do not help us, because the expensive part is the first 30 days, not the archive. We are paying Analytics-tier prices for lines nobody reads.

### 2. Most of what we log is not actionable

An actionable log line answers "what do I do now?". Most of ours answer "something happened". A line that nobody can act on is a line that should either be a metric or not exist.

### 3. Levels are currently chosen arbitrarily

There has never been written guidance on what each level means, so each service made it up. The result is measurable across the fleet today:

| Level | Statements fleet-wide | Expectation |
|---|---|---|
| `ERROR` | ~222 | Should be the **rarest** level; instead it roughly equals `INFO` |
| `INFO` | ~216 | |
| `WARN` | ~95 | |
| `DEBUG` | ~65 | |
| `TRACE` | 1 | Effectively unused, so there is no "off by default" tier |

`ERROR` being as common as `INFO` is the clearest symptom: if every `ERROR` paged someone, we would page constantly, so in practice **no `ERROR` pages anyone**. The level has lost its meaning.

### 4. We use logs to collect metrics

This is the single biggest source of avoidable volume. `VehiclePositionPublisher` in `transitdata-gtfsrt-full-publisher` emits **seven `INFO` lines on every publish cycle**, and every one of them is a measurement:

```java
logger.info("Starting GTFS Full dataset publishing. Cache size: {}, new vehicle positions: {}", ...);
logger.info("Cache size after merging: {}", vehiclePositionCache.size());
logger.info("Current time: {}, min vehicle timestamp in cache: {}, max ...", ...);
logger.info("Vehicle positions published in {}ms", Duration.ofNanos(...).toMillis());
logger.info("Removing vehicle positions older than {} seconds from cache", maxAge.getSeconds());
logger.info("Cache size before removing old vehicle positions: {}, after: {}", ...);
```

That is a gauge, a histogram and a counter wearing log costumes. As logs they are expensive, unqueryable in aggregate, and impossible to alert on sensibly. As three Prometheus metrics they would be cheap, graphable, and alertable — and the log lines would disappear entirely.

### 5. There is nowhere else for a measurement to go

The reason people log metrics is that **no service in the fleet exposes a metrics endpoint.** Verified: `mqtt-pulsar-gateway` is the only repository with Micrometer on the classpath, and its Actuator exposure is `include: health,info` — `prometheus` is not exposed.

Instead, metrics are reconstructed **from the outside** by two side-channel services: `transitdata-metrics-exporter` polls GTFS-RT URLs and MQTT brokers, and `transitdata-monitor-data-collector` polls Pulsar and MQTT and pushes Azure Monitor custom metrics. Both are black-box probes. Neither can see queue depth, cache size, parse-failure rate, or handler latency, because the services never publish them.

**Telling developers to stop logging metrics without giving them a metrics endpoint will not work.** Section 4 of *How?* is therefore a hard prerequisite, not an optional extra.

### 6. Verbose logging is a symptom, not just a cost

Code that is hard to test and hard to reason about accumulates `log.debug` calls as a substitute for both. Cutting log volume tends to surface the places where the real fix is a test or a clearer boundary. We should treat a service that needs heavy logging to be operable as a service with a design problem.

### 7. The current configuration cannot be tuned without a rebuild

There are **23 near-duplicate `logback.xml` files** in the fleet — 22 services plus the canonical one in `transitdata-common` that they all shadow. Every one of them hardcodes:

```xml
<root level="info">
```

There is no environment-variable override, so changing a level in dev requires a code change, a PR, a build and a deploy. Every file also pins `<timestampFormatTimezoneId>Etc/UTC</timestampFormatTimezoneId>`, which matters for alerting (see *How?* §3).

---

## How?

### 1. The decision rule: log, metric, or neither

Ask in this order:

1. **Is it a number that changes over time?** → Prometheus metric. Never a log line. Counts, sizes, durations, rates, queue depths, cache occupancy.
2. **Is it a discrete, surprising event a human would want to read the story of?** → Log line. Startup, shutdown, config resolution, connection loss, a message that failed to parse.
3. **Is it neither?** → Delete it.

The shorthand: **logs are for narrative, metrics are for measurement.** If a line contains a number that you would ever want to graph, sum, or average, it is a metric in the wrong place.

A log line and a metric can legitimately coexist for the same event — increment `messages_failed_total{reason="malformed"}` *and* log one `WARN` with the offending payload identifier. The metric answers "how often"; the log answers "which one, and why".

### 2. Level definitions

Each level is defined by an operational contract and a volume budget. The budget is the important half: a level whose budget is routinely exceeded is being misused.

| Level | Means | Steady-state budget | Environments | Alerting |
|---|---|---|---|---|
| `ERROR` | The service could not do its job and **a human must intervene**. Data was lost, a dependency is unreachable beyond retry, or state is corrupt. | **< 1 per hour per service.** Zero is the normal value. | dev, stage, prod | **Immediate, throttled page** |
| `WARN` | Something unexpected happened, the service **recovered or degraded gracefully**, and nobody needs to act right now — but a sustained rise means something is wrong. | < 10 per minute per service | dev, stage, prod | **Rate-based**, on deviation |
| `INFO` | Lifecycle and irreversible state change. Startup, shutdown, resolved configuration, leader election, connection established/lost, scheduled job boundaries. | **< 1 per minute per service.** Must not scale with message throughput. | dev, stage, prod | None (retained for context) |
| `DEBUG` | Detail needed to diagnose a problem you are actively chasing. Loop boundaries, branch decisions, intermediate values. | < 100 per second, and **off by default everywhere** | dev only, enabled on demand | None |
| `TRACE` | Per-message, per-iteration firehose. | Unbounded | **Local development only** | None |

**On `FATAL`:** the fleet uses SLF4J with Logback, and **SLF4J has no `FATAL` level** — `ERROR` is the ceiling. Only Log4j2 offers `FATAL`. Rather than introduce a marker to fake it, treat unrecoverable startup failure as `ERROR` followed by a non-zero exit: the pod terminating is a far stronger and more reliable signal than a log level, and Kubernetes already alerts on `CrashLoopBackOff`.

**The `INFO` rule that matters most:** *`INFO` volume must be independent of traffic volume.* A service handling 10 messages/second and one handling 10,000 messages/second should emit roughly the same number of `INFO` lines. Any `INFO` inside a per-message path is a bug. This single rule accounts for most of the volume we are paying for.

### 3. Connecting levels to alerting

**`ERROR` → immediate alert, throttled.** One `ERROR` should be able to page. To make that survivable, alerts carry the **first `n` occurrences** within a window and then suppress the remainder with a count, so a dependency outage produces one actionable notification rather than a flood. This is only viable once `ERROR` volume is brought back inside its budget — do not enable paging before completing the rollout in §7.

**`WARN` → rolling count with a deviation threshold.** Track `WARN` count per service over a fixed window (start at **10 minutes**; tune per service) and alert when the count departs materially from its recent norm. Typical `WARN` sources — malformed MQTT source messages, dropped broker connections — are exactly the things where the *rate* is the signal and any individual occurrence is noise.

Prefer a **counter metric per warning category** over parsing log text for these. `messages_rejected_total{reason="malformed"}` is cheaper to alert on, more precise, and does not break when someone rewords the message.

**`INFO` → no alerts, but track the rate.** A step change in `INFO` volume usually means a crash loop or a regression that moved a line into a hot path. Watch it as a health signal on the logging system itself.

**Use local time (`Europe/Helsinki`) for dynamic-threshold alerts.** Our traffic follows the Finnish transit day. With UTC, every DST transition shifts the daily pattern by an hour and dynamic baselines misfire for days afterwards. Note this contradicts the current `Etc/UTC` setting in all 29 `logback.xml` files — **log timestamps should stay UTC** for correlation; it is the *alert evaluation window* that should be local. Keep the two decisions separate and deliberate.

### 4. Expose Prometheus metrics — prerequisite for everything else

Services must publish their own metrics rather than having them inferred by external polling.

For Spring Boot services, add `micrometer-registry-prometheus` and expose the endpoint:

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
```

For plain-Java services, use the Micrometer Prometheus registry with a minimal HTTP server on the existing management port.

**The baseline every service should publish:**

| Metric | Type | Replaces |
|---|---|---|
| `messages_received_total{source}` | counter | per-message `DEBUG`/`INFO` |
| `messages_published_total{topic}` | counter | "Message acked", "Mqtt message delivered" |
| `messages_failed_total{reason}` | counter | repeated parse-failure `WARN`s |
| `message_processing_duration_seconds` | histogram | `"published in {}ms"` |
| `cache_entries` | gauge | `"Cache size after merging: {}"` |
| `connection_state{dependency}` | gauge | connection churn logging |

Once these exist, the corresponding log lines are deleted — not downgraded. A downgraded line still costs money in dev and still tempts someone to re-enable it.

### 5. Configuration changes

**Make the level configurable per environment.** Replace the hardcoded root level in each `logback.xml`:

```xml
<root level="${LOG_LEVEL:-info}">
```

Set `LOG_LEVEL` in the AKS manifests: `info` in stage and prod, `info` in dev with `debug` available on demand without a rebuild.

**Consolidate the 22 shadowing files.** The canonical configuration belongs in `transitdata-common`, which already owns the shared JSON layout, so a change to the log format is one PR rather than 29. Services keep a local file only where they genuinely deviate.

**Keep structured JSON output.** The existing `JsonLayout` + `JacksonJsonFormatter` setup is correct and should be preserved — structured logs are what make field-based alerting possible without regex.

### 6. Writing rules

- **Always use parameterized logging**, never string concatenation. `log.debug("Parsing topic: " + topic)` builds the string even when `DEBUG` is disabled; `log.debug("Parsing topic: {}", topic)` does not. There are **46 such concatenations across 25 files** today — fix them as they are touched.
- **One event, one line.** Do not log the same failure at three layers as it propagates. Log where it is handled, not where it is thrown.
- **Include the identifier, not the payload.** A vehicle id or message id makes a line traceable; a full serialized payload makes it expensive and risks leaking data.
- **No personal data.** Vehicle and trip identifiers are operational; anything that could identify a passenger must never reach a log.
- **Log the cause, not the symptom.** `"Failed to connect to Pulsar at {}: {}"` beats `"Something went wrong"`.
- **Exceptions belong in the exception parameter**, not interpolated into the message — `log.error("Failed to parse topic {}", topic, e)` preserves the stack trace as structured data.

### 7. Throttling — only if still needed

Do not start here. Volume should be fixed at the source; throttling is what remains after the real work.

- **Logback's `DuplicateMessageFilter` is not usable for us.** It suppresses repeats of the last `n` distinct messages, so with our message mix it removes either almost everything or almost nothing depending on `n`. Do not adopt it.
- **Log4j2's `BurstFilter` is the better fit** — it enforces a rate limit per level and drops the excess, which matches "alert on the first few, suppress the flood". Since all services log through the SLF4J API, **the application code would not change**; only the binding and configuration would. The cost is real, though: our `logback-jackson`/`JsonLayout` configuration would have to be reimplemented for Log4j2 across the fleet.

Treat the Log4j2 migration as a **last resort**, to be evaluated only if §§1–6 leave volume above target.

### 8. Retention tiers

| Environment | Level collected | Tier | Rationale |
|---|---|---|---|
| Development | `INFO` (`DEBUG` on demand) | Basic Logs | No alerting needed; 1/5 the cost |
| Staging | `INFO` | Basic Logs | Same |
| Production | `INFO` | Analytics Logs | Alerting requires it |

Basic Logs does not support alerting. That is acceptable in dev and stage, where a human is already looking. It is the main lever available for cost, and it becomes viable in dev precisely when `DEBUG`/`INFO` volume has been brought inside budget.

### 9. Rollout

1. **Measure first.** Rank services by actual log bytes produced in production over a representative week. Do not rank by log statement count — this audit found only ~600 statements fleet-wide, which means volume comes from a handful of lines in hot paths, not from many lines. The ranking will not match intuition.
2. **Fix the top 3–4 offenders.** For each: add the Prometheus metrics from §4, delete the metrics-as-logs lines, move per-message lines to `DEBUG` or remove them, and enforce the `INFO`-independent-of-throughput rule. `transitdata-gtfsrt-full-publisher` is a known starting point.
3. **Stop and re-measure.** If `DEBUG`/`INFO` volume has dropped enough that development can run on Basic Logs, the cost objective is met — **stop optimizing here.**
4. **Only then** evaluate Log4j2 `BurstFilter` (§7).
5. **Then** enable `ERROR` paging and `WARN` rate alerts, once volumes are inside budget and the alerts will not immediately be muted.

Steps 1–3 are expected to deliver most of the benefit. Do not begin step 4 before step 3 has been measured.

### 10. Implement this as a cross-cutting concern, not as 34 separate code changes

**Verdict: yes for the JVM fleet — one library reaches 24 of 24 JVM services. No for the 10 non-JVM services, and no for the part that actually matters most.**

#### `transitdata-common` is a universal JVM dependency

All 21 Java and all 3 Kotlin services declare `fi.hsl:transitdata-common`. There is no JVM service a change there would miss.

#### It already owns every seam this proposal needs

| Seam | File | What it delivers with no per-service code |
|---|---|---|
| Health endpoint | `health/HealthServer.java` | Already runs a `com.sun.net.httpserver.HttpServer` with `createContext(...)`. A `/metrics` context exposes Prometheus in **every service** — no new port, no new server, no new manifest plumbing. |
| Message path | `pulsar/IMessageHandler.java` | A single-method interface, `void handleMessage(Message)`. A decorator in the library yields `messages_received_total`, `messages_failed_total` and `message_processing_duration_seconds` for every consumer. |
| Client lifecycle | `pulsar/PulsarApplication.java` | Owns `createConsumer` / `createProducers`, so `messages_published_total` and `connection_state` are instrumentable centrally. |
| Parsers | `hfp/HfpParser.java`, `passengercount/PassengerCountParser.java` | `messages_failed_total{reason="malformed"}` at the point failures actually happen. |
| Log config | `src/main/resources/logback.xml` | Already ships the canonical JSON layout. |

**Five of the six baseline metrics in §4 can therefore be delivered by a single PR to `transitdata-common`**, with consuming services changing nothing but a version number.

#### What cannot be centralized

This is where the real effort sits, and pretending otherwise would make the plan fail:

1. **Deleting metrics-as-logs lines.** A library can *add* a metric; it cannot *remove* someone's `logger.info("Cache size after merging: {}", ...)`. Stripping the seven `INFO` lines out of `VehiclePositionPublisher` is per-service work by nature.
2. **Domain metrics.** Cache occupancy, dataset age, per-route counts — the library has no knowledge of these.
3. **The 10 non-JVM services** (8 TypeScript, 2 Python). No shared library exists for them. Worth noting the TypeScript side has *already* solved the configurability half: `transitdata-partial-apc-expander-combiner` and `transitdata-partial-apc-pbf-json-transformer` read `PINO_LOG_LEVEL` from their AKS manifests. On runtime-configurable levels the JVM fleet is the laggard, not the leader.
4. **Version bumps.** Services pin `common.version` across five versions today — 2.0.3, 2.0.4, 2.0.5, 2.0.7 and 3.0.0. Each still needs a bump PR. But that is a one-line change Dependabot raises automatically once the `maven` ecosystem from the [Dependabot proposal](Dependabot-Improvements.md) is in place — not a code review of business logic.
5. **`logback.xml` shadowing.** 22 services ship their own `src/main/resources/logback.xml`, each shadowing the copy inside `transitdata-common`, because Logback takes the first configuration it finds on the classpath. Services must **delete** their local file to inherit the canonical one — a per-repo change, but a file deletion rather than an edit.

#### Other cross-cutting levers, ranked by leverage

| Lever | Reaches | Cost | Verdict |
|---|---|---|---|
| `transitdata-common` library | 24 JVM services | 1 PR + 24 version bumps | **Primary vehicle** |
| AKS manifests (`LOG_LEVEL` env) | All 34 services, any language | Manifest edit per deployment | **Use** — needs no code change at all |
| Shared CI workflow (static analysis) | All Java + Kotlin repos | 1 PR to `ci-cd-java.yml` | **Use for enforcement** |
| Base Docker images (`ENV LOG_LEVEL=info`) | All JVM services | 1 PR | Marginal — manifests override it anyway |
| Collector-side filtering (drop at ingestion) | Everything | Collector config | **Rejected** — hides the problem, still pays compute, and leaves metrics-as-logs untouched |
| Java agent / bytecode weaving | All JVM | High | **Rejected** — violates *use boring technology* |

The shared workflow already runs `mvn spotless:check` under a "Check code format and lint" step, which is a ready-made place to hang a logging rule. A Checkstyle or PMD rule banning string concatenation inside `log.*(...)` would enforce §6 across every Java and Kotlin repo from one file, and **fail the build** rather than depending on a reviewer noticing.

#### Recommended split

- **Centralized — one PR each:** metrics endpoint, message-path metrics, parse-failure metrics, canonical Logback config, static-analysis rule.
- **Per repo, mechanical — reviewable in minutes:** bump `common.version`, delete local `logback.xml`, add `LOG_LEVEL` to the manifest.
- **Per repo, real work — only the top offenders:** delete metrics-as-logs lines, move per-message `INFO` to `DEBUG`, add domain metrics.

This turns *"change 34 repositories"* into *"change one library, mechanically touch 24, and do genuine work in 3–4."*


### 11. Open questions

- **`WARN` window length** — 10 minutes is the proposed starting point; per-service tuning may be needed.
- **Static thresholds vs dynamic baselines for `WARN`.** Dynamic adapts to seasonality but misfires around DST and service changes; static is predictable but needs maintenance. Recommendation: start static per service, move to dynamic only where the traffic pattern justifies it.
- **Does alerting survive the move to Basic Logs?** If we ultimately want no log-based alerting at all — alerting on metrics instead — production could move to Basic Logs too, and the cost picture changes substantially. This is the largest open decision in this proposal and should be settled before the retention tiers in §8 are treated as final.
- **Who owns the alert rota**, and what the acceptable page rate is. An `ERROR` that pages is only meaningful if someone is on the receiving end.

---

## Follow-up items

Concrete work required before log levels can be standardized. **[X]** marks a cross-cutting item — one change, fleet-wide effect.

### Phase 1 — Make the target reachable

Nothing below this line can be enforced until these exist. Items 2–5 are all one PR to the same repository and should ship as one release.

| # | Item | Where | Type |
|---|---|---|---|
| 1 | Measure actual log **bytes** per service in production over a representative week and rank the fleet. Do not rank by statement count — volume comes from a few hot-path lines, so the ranking will not match intuition. | Azure Monitor | Investigation |
| 2 | Add Micrometer + `micrometer-registry-prometheus`; expose `/metrics` through the existing `HealthServer` | `transitdata-common` | **[X]** |
| 3 | Add an `IMessageHandler` instrumenting decorator emitting `messages_received_total`, `messages_failed_total`, `message_processing_duration_seconds` | `transitdata-common` | **[X]** |
| 4 | Instrument `PulsarApplication` producers/consumer for `messages_published_total` and `connection_state` | `transitdata-common` | **[X]** |
| 5 | Make the canonical `logback.xml` use `${LOG_LEVEL:-info}` and document the inheritance rule | `transitdata-common` | **[X]** |
| 6 | Cut a `transitdata-common` release carrying items 2–5 | `transitdata-common` | **[X]** |

### Phase 2 — Adopt across the fleet

Mechanical. Each item is a small PR per repository; none requires understanding the service's business logic.

| # | Item | Scope | Type |
|---|---|---|---|
| 7 | Bump `common.version` to the Phase 1 release | 24 JVM repos | Per repo (Dependabot-automatable) |
| 8 | Delete the local `src/main/resources/logback.xml` so the canonical config is inherited | 22 repos | Per repo |
| 9 | Add `LOG_LEVEL` env var to every Deployment (`info` in all environments to start) | AKS manifests | Per deployment |
| 10 | Add a `prometheus` scrape annotation or `ServiceMonitor` for the new `/metrics` endpoint | AKS manifests | Per deployment |
| 11 | Expose `prometheus` in `mqtt-pulsar-gateway`'s Actuator config — it has Micrometer already but publishes only `health,info` | `mqtt-pulsar-gateway` | Per repo |

### Phase 3 — Fix the offenders

The only phase requiring real engineering judgement. Scope to the top 3–4 services from item 1.

| # | Item | Scope | Type |
|---|---|---|---|
| 12 | Replace metrics-as-logs with real metrics and **delete** the log lines. Known starting point: the seven per-cycle `INFO` lines in `VehiclePositionPublisher` | Top offenders | Per repo |
| 13 | Move per-message `INFO`/`DEBUG` out of hot paths; enforce *`INFO` must not scale with throughput* | Top offenders | Per repo |
| 14 | Audit `ERROR` usage — with `ERROR` and `INFO` at near-parity fleet-wide, most `ERROR`s are misclassified `WARN`s | All JVM repos | Per repo |
| 15 | Fix the 46 string-concatenation log calls across 25 files | 25 repos | Per repo (or item 17) |
| 16 | **Re-measure.** If dev now fits Basic Logs, stop — do not proceed to Phase 5. | Azure Monitor | Investigation |

### Phase 4 — Prevent regression

| # | Item | Where | Type |
|---|---|---|---|
| 17 | Add a Checkstyle/PMD rule banning string concatenation in `log.*()` calls to the shared "Check code format and lint" step | `transitdata-shared-workflows` | **[X]** |
| 18 | Extend that rule to flag `log.info` inside classes implementing `IMessageHandler` | `transitdata-shared-workflows` | **[X]** |
| 19 | Add the logging rules to the modernization checklist so every migrating service adopts them | `team-infodevops` | **[X]** |

### Phase 5 — Alerting and cost, once volumes are inside budget

| # | Item | Where | Type |
|---|---|---|---|
| 20 | Define per-service `WARN` rate thresholds and the `ERROR` paging rota | Azure Monitor | Investigation |
| 21 | Enable throttled `ERROR` paging — **only after** item 16 confirms `ERROR` is inside budget | Azure Monitor | Config |
| 22 | Set alert evaluation windows to `Europe/Helsinki`; leave log timestamps in UTC | Azure Monitor | Config |
| 23 | Move dev and stage to Basic Logs | Azure Monitor | Config |
| 24 | Decide whether production alerting can move to metrics entirely, allowing prod onto Basic Logs | Team decision | Investigation |
| 25 | Evaluate Log4j2 `BurstFilter` — **only if** item 16 shows volume still above target | `transitdata-common` | **[X]** |

### Non-JVM follow-ups

The 10 TypeScript and Python services are not reached by any of the above.

| # | Item | Scope | Type |
|---|---|---|---|
| 26 | Apply the same level semantics and metric-vs-log rule to Pino-based services; several already read `PINO_LOG_LEVEL` | 8 TypeScript repos | Per repo |
| 27 | Expose Prometheus metrics from TypeScript and Python services | 10 repos | Per repo |
| 28 | Decide whether a shared TypeScript logging/metrics package is worth creating, or whether 8 repos is below the threshold where a library pays for itself | Team decision | Investigation |

---

## Summary

| Aspect | Decision |
|---|---|
| **Log vs metric** | Numbers that change over time are metrics; discrete surprising events are logs; everything else is deleted |
| **`ERROR`** | Human must intervene · < 1/hour · immediate throttled page |
| **`WARN`** | Recovered or degraded · < 10/min · rate-based deviation alert |
| **`INFO`** | Lifecycle only · < 1/min · **must not scale with throughput** |
| **`DEBUG`** | Diagnosis · off by default · dev on demand |
| **`TRACE`** | Local development only |
| **`FATAL`** | Not available in SLF4J — use `ERROR` + non-zero exit |
| **Metrics** | Prometheus endpoint per service; hard prerequisite, not optional |
| **Alert timezone** | `Europe/Helsinki` for evaluation windows; UTC for log timestamps |
| **Throttling** | Log4j2 `BurstFilter` if needed; Logback `DuplicateMessageFilter` rejected |
| **Cost** | Basic Logs in dev and stage; Analytics in prod while alerting depends on it |
| **Delivery** | Cross-cutting via `transitdata-common` — one PR reaches all 24 JVM services |
| **Not cross-cuttable** | Deleting metrics-as-logs lines, domain metrics, and the 10 non-JVM services |

## Expected outcomes

- Log spend reduced by removing metrics-as-logs and per-message lines rather than by blunt level suppression
- `ERROR` restored to a level that can page someone
- Statistics become graphable and alertable instead of buried in log text
- Services observable from the inside, rather than inferred by external black-box polling
- A written rule that makes the level choice obvious at the point of writing the line

## Related proposals

- Microservice modernization checklist — logging configuration is part of service modernization. *(Currently unmerged: lives on `feature/76478_modernization-checklist-for-microservices`, not on `main`.)*
- [Docker base images](Docker-Base-Images-Proposal.md) — base images carry logging and monitoring conventions
- [CI/CD design](CI-CD-Design-Proposal.md)

Aligns with the architectural principles [*Prioritize quality*](../architectural-principles.md), [*Use boring technology*](../architectural-principles.md) — Prometheus and SLF4J are established, not novel — and [*Shift left*](../architectural-principles.md), by making the level decision explicit when the line is written rather than during an incident.
