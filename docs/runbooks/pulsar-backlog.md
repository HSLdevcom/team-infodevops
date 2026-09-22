# Pulsar messages are piling up

| Alert | Meaning |
|---|---|
| `PulsarSubscriptionBacklogGrowing` | A consumer is falling behind |
| `PulsarSubscriptionBacklogCritical` | A consumer has effectively stopped |
| `PulsarChronicBacklogWorsening` | A subscription that is always behind is now worse than usual |
| `PulsarStorageHigh` | A topic is using more disk than expected |

A backlog means messages are arriving but **not being consumed** — the producer side is fine. If
nothing is being published instead, see [pulsar-rate-drop](./pulsar-rate-drop.md).

## What it means

The alert names the **subscription**, which tells you which consumer is stuck. Subscription names
map onto deployments fairly directly — `transitdata_hfp_parser` → `transitdata-hfp-parser`. While a
consumer is stuck, whatever it feeds downstream is not updating.

**Subscriptions beginning `transitlog_` are not ours** — those consumers live outside this cluster.
Do not restart anything; contact the Transitlog team.

Some subscriptions carry a large backlog as their normal state (e.g. hourly batch sinks).
`PulsarChronicBacklogWorsening` is the alert for those — a big number there is expected, so it only
fires when the backlog has grown beyond its usual range.

## Dashboards

- [Pulsar Overview](https://grafana-infosys-prod-dpbde9bwdscpf8b9.weu.grafana.azure.com/d/bf7ckpemufy0wa) — is the backlog still climbing (consumer stopped) or levelling off (consumer alive but slow)?

## Likely causes

1. **The consumer crashed or is crash-looping** — check the pod first, always.
2. **The consumer is running but stuck** — deadlocked or blocked on something downstream like a
   database or Redis. The pod looks healthy but the logs stop moving.
3. **The consumer is too slow** for current volume — backlog grows during busy periods and drains
   overnight.
4. **It is catching up after an earlier outage** — backlog large but falling. Nothing to do.

## What to do

```sh
K="kubectl --context aks-aksinfosys-prod-weu-tunnel"   # dev: aks-aksinfosys-dev-001-tunnel

$K -n transitdata get pods | grep -i <consumer>
$K -n transitdata logs deploy/<consumer> --tail=100
```

For a stuck consumer, restart it and watch the backlog drain:

```sh
$K -n transitdata rollout restart deploy/<consumer>
```

A restart that fixes it and then recurs is not a fix — capture the logs from before restarting.
If the consumer is healthy but too slow, it needs more resources or parallelism, which is a change
in [`transitdata-aks-deploy`](https://github.com/HSLdevcom/transitdata-aks-deploy).

For **high storage**, look for a backlog on the same topic first — fixing the consumer usually makes
storage recover on its own as messages are acknowledged. High storage with no backlog is a retention
question instead.

## Who to contact

Team first. `transitlog_*` subscriptions go to the **Transitlog team**. If every subscription is
backing up at once, the problem is Pulsar itself rather than the consumers — check broker and bookie
health on the Pulsar dashboards, and involve the platform team if the cluster is unhealthy.
