# Runbooks

One file per kind of alert. When an alert fires in Slack, its `runbook_url` link brings you here.

The goal is simple: you see an alert, open the runbook, and get a rough idea of what is wrong and
what to do — without having to remember how the whole pipeline fits together.

Each runbook follows the same shape:

- **What it means** — who is affected and how badly
- **Dashboards** — where to look
- **Is this normal?** — some feeds stop at night on purpose
- **Likely causes** — most common first
- **What to do** — the commands to run
- **Who to contact** — when it is not ours to fix

## Environments

| | dev | prod |
|---|---|---|
| Slack channel | `transitdata-dev-monit` | `azure-transitdata-monitoring` |
| Grafana | [grafana-202511110445-we](https://grafana-202511110445-we-hecnd9dvgugeaxcj.weu.grafana.azure.com) | [grafana-infosys-prod](https://grafana-infosys-prod-dpbde9bwdscpf8b9.weu.grafana.azure.com) |
| AKS cluster | dev cluster | prod cluster |
| Namespace | `transitdata` | `transitdata` |

Both clusters are private, reached through a bastion tunnel — point `kubectl` at the right cluster
before running the commands below. The examples target the prod cluster; use the dev cluster for a
dev alert.

## Who to contact

| Area | Owner |
|---|---|
| Transitdata pipeline (our services) | InfoDevOps / Transitdata team |
| Prod GTFS-RT output MQTT broker `predin.rt.hsl.fi` (trip updates, service alerts) | Contrasec |
| `transitlog_*` Pulsar subscriptions (consumers outside this cluster) | Transitlog team |
| AKS cluster, nodes, networking, egress | Platform team (`azure-infra-aks` owners) |
| PubTrans ROI/DOI database (bus & tram estimates) | `tilhi@hsl.fi` |
| `realtime.hsl.fi` GTFS-RT feed endpoints | HSL realtime feed owner |

## Index

| Runbook | Alerts it covers |
|---|---|
| [metrics-exporter-down](./metrics-exporter-down.md) | `TransitdataMetricsExporterDown` |
| [mqtt-no-messages](./mqtt-no-messages.md) | `ServiceAlertsFeedSilent`, `FullApcFeedSilent`, `MetroHfpFeedSilent`, `MqttFeedSilent`, `MqttNightlyFeedSilent` |
| [pulsar-rate-drop](./pulsar-rate-drop.md) | `PubtransDepartureEstimatesSilent`, `MetroEstimatesSilent`, `PulsarTopicRateDropped` |
| [gtfsrt-feed-problems](./gtfsrt-feed-problems.md) | `GtfsrtFeedScrapeFailure`, `GtfsrtFeedStale{VP,TU,SA}`, `GtfsrtScrapeErrorRateHigh` |
| [mqtt-broker-connectivity](./mqtt-broker-connectivity.md) | `MqttBrokerDisconnected`, `MqttHfpRedundantPairBothDown`, `MqttConnectionUnstable` |
| [pulsar-backlog](./pulsar-backlog.md) | `PulsarSubscriptionBacklog{Growing,Critical}`, `PulsarChronicBacklogWorsening`, `PulsarStorageHigh` |
| [pod-health](./pod-health.md) | `PodCrashLooping`, `PodNotReady`, `ContainerOOMKilled` |
| [resource-saturation](./resource-saturation.md) | `HighMemoryUsage`, `HighCPUUsage` |
