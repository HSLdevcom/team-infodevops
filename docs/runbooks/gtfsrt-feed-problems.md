# GTFS-RT feed problem

| Alert | Meaning |
|---|---|
| `GtfsrtFeedScrapeFailure` | The feed cannot be fetched at all |
| `GtfsrtFeedStaleVP` / `TU` / `SA` | The feed responds, but the data in it is old |
| `GtfsrtScrapeErrorRateHigh` | The feed responds sometimes and fails sometimes |

These are the feeds Google Maps, Reittiopas and stop displays read. A problem here reaches
passengers within minutes.

## What it means

- **Scrape failure** — the feed endpoint is unreachable. Consumers get nothing.
- **Stale** — the feed is being fetched fine and returns data, just *old* data. The endpoint is
  healthy; something upstream has stopped producing fresh content.
- **High error rate** — intermittent, usually a flaky endpoint or network.

## Dashboards

- [GTFS-RT Overview](https://grafana-infosys-prod-dpbde9bwdscpf8b9.weu.grafana.azure.com/d/gtfsrt-feed-monitoring-prod) — feed status, timestamp age, and scrape results by type
- [Pulsar Overview](https://grafana-infosys-prod-dpbde9bwdscpf8b9.weu.grafana.azure.com/d/bf7ckpemufy0wa) — for staleness, follow the topics feeding that output

## First question: one feed, or all of them?

The GTFS-RT dashboard answers this, and it decides where to look:

- **All feeds failing at once** — the problem is on our side, not the feeds'. Go to
  [metrics-exporter-down](./metrics-exporter-down.md) and check egress.
- **One feed** — that feed's publisher or its upstream has a problem.

The three feed types move at very different speeds — vehicle positions update every second or so,
service alerts only every few minutes. A service-alerts feed that looks slow next to vehicle
positions is normal.

## Likely causes

1. **The metrics exporter is unhealthy** — if everything failed at once. See
   [metrics-exporter-down](./metrics-exporter-down.md).
2. **Upstream pipeline stall** — staleness with successful fetches. The usual cause of stale; the
   fault is a stalled processor or growing backlog upstream, and there is often a Pulsar alert
   firing at the same time that names the real cause. See [pulsar-rate-drop](./pulsar-rate-drop.md).
3. **The feed publisher is down** — one feed, fetch failing.
4. **Flaky network or unstable endpoint** — intermittent errors rather than total failure.

## What to do

Most GTFS-RT problems are not fixed in the GTFS-RT layer. Decide whether it is **reachability** (our
side or theirs) or **freshness** (upstream), then follow that thread. Restarting a publisher for a
stale feed only helps if that publisher is the thing that stalled. If a feed endpoint is genuinely
down, note the start time — consumers will ask.

## Who to contact

Team first. A stale feed is almost always our upstream pipeline (follow the Pulsar thread). An
unreachable `realtime.hsl.fi` endpoint belongs to the HSL realtime feed owner.
