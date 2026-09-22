# Pulsar topic has gone silent

| Alert | Meaning |
|---|---|
| `PubtransDepartureEstimatesSilent`, `MetroEstimatesSilent`, `PulsarTopicRateDropped`, `PulsarNightlyTopicRateDropped`, `PulsarLowVolumeTopicSilent` | Nothing is being published to a topic — the producer has stopped |

This is a **producer** problem, not a consumer one. If messages are arriving but piling up
unconsumed, see [pulsar-backlog](./pulsar-backlog.md) instead. The alert names the topic.

## What it means

| Topic | Consequence |
|---|---|
| `source-pt-roi/departure`, `source-pt-roi/arrival` | Bus and tram predictions stop updating — passengers see this directly |
| `source-metro-ats/metro-estimate` | Metro arrival/departure predictions stop |
| `gtfs-rt/feedmessage-*` | The output feed itself stops updating |
| `hfp/*`, `hfp-mqtt-raw/*` | Vehicle positions or APC data stop flowing through the pipeline |

A stalled topic starves everything downstream, so expect more alerts shortly. If several fire at
once, **look for the earliest one in the chain** — the rest are usually consequences.

## Dashboards

- [Pulsar Overview](https://grafana-infosys-prod-dpbde9bwdscpf8b9.weu.grafana.azure.com/d/bf7ckpemufy0wa) — check the topic immediately upstream too; if that is also at zero, the real fault is further back

## Is this normal?

Metro topics go quiet overnight — metro stops around 00:10 and resumes around 04:50 (later on
Sunday). The APC output topics also go quiet for about an hour at night.
`PulsarNightlyTopicRateDropped` and `PulsarLowVolumeTopicSilent` already allow for those gaps, so
if one of those fired the silence is genuinely abnormal.

## Likely causes

The producer is a service in the `transitdata` namespace; the topic name points at it —
`source-pt-roi/*` from the pubtrans sources, `metro-ats*` from the metro-ats services.

1. **The producer service is down or crash-looping** — most common. Check the pod first.
2. **The upstream source is unreachable** — the source services poll ptROI, DOI and OMM; if the
   database or API is down the pod stays `Running` and healthy while producing nothing. The logs
   are the only signal.
3. **Scheduled silence** — metro or APC at night.
4. **Pulsar itself** — rare, and it would affect many topics at once.

## What to do

```sh
K="kubectl --context aks-aksinfosys-prod-weu-tunnel"   # dev: aks-aksinfosys-dev-001-tunnel

$K -n transitdata get pods | grep -E "pubtrans|metro-ats|hfp"
$K -n transitdata logs deploy/<producer> --tail=100
```

For a dead producer, restart it and confirm the rate recovers on the dashboard within a couple of
minutes:

```sh
$K -n transitdata rollout restart deploy/<producer>
```

A restart that helps and then recurs is not a fix — capture the logs from before restarting. For an
unreachable upstream source, this is not repairable from our side: confirm, note the start time, and
contact the source owner. Output recovers on its own once the source returns.

## Who to contact

Team first, then the owner of the upstream data source: **`tilhi@hsl.fi`** for the PubTrans ROI/DOI
database (`source-pt-roi/*`), the metro ATS / OMM data owners for the metro and cancellation feeds.
