# Metrics exporter is down

| Alert | Meaning |
|---|---|
| `TransitdataMetricsExporterDown` | The `transitdata-metrics-exporter` pod is not reporting |

## What it means

This pod produces every MQTT and GTFS-RT measurement we have. While it is down, those alerts
**cannot fire** — so silence from them means nothing, and the pipeline is effectively unmonitored
until it comes back. The pipeline itself is not broken; we have just lost the ability to see if it
breaks. (Pulsar and Kubernetes alerts come from elsewhere and are unaffected.)

## Dashboards

- [MQTT message counts](https://grafana-infosys-prod-dpbde9bwdscpf8b9.weu.grafana.azure.com/d/mqtt-message-counts-prod) — goes flat across the board when the exporter is down

## What to do

```sh
K="kubectl"   # point kubectl at the prod cluster (dev: the dev cluster)

$K -n transitdata get pods -l app=transitdata-metrics-exporter
$K -n transitdata describe pod -l app=transitdata-metrics-exporter | tail -40
$K -n transitdata logs -l app=transitdata-metrics-exporter --tail=100
```

Check **Last State** in the describe output first — it usually tells you which case you are in.

## Likely causes

1. **Out of memory** (`Last State: OOMKilled`) — the most common cause. It restarts on its own, so
   the alert often clears before you look. If it keeps recurring, the memory limit is the thing to
   fix, not each individual kill. Bump it in `manifests/transitdata-metrics-exporter.yaml` in
   [`transitdata-aks-deploy`](https://github.com/HSLdevcom/transitdata-aks-deploy).
2. **Bad configuration** — it reads its broker and feed lists from the
   `transitdata-metrics-exporter` ConfigMap at startup; malformed JSON kills it on boot and the log
   says so. Usually follows a recent change.
3. **Not being scraped** — the pod is `Running` but nothing collects from it, usually after a label
   change. Check the Service has endpoints:
   ```sh
   $K -n transitdata get svc,endpoints transitdata-metrics-exporter
   ```
   An `Endpoints` object with no addresses means the Service selects nothing.
4. **Node disruption** (drain, upgrade, eviction) — it reschedules itself and the alert clears.

Once fixed, metrics reappear within seconds and the alert clears about ten minutes later.

## Who to contact

Team first — this is our workload. If the pod cannot be scheduled at all, that is a cluster issue
for the platform team (`azure-infra-aks` owners).
