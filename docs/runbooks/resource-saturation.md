# Container near its memory or CPU limit

| Alert | Meaning |
|---|---|
| `HighMemoryUsage` | A container is close to being killed for using too much memory |
| `HighCPUUsage` | A pod is being throttled and running slower than it should |

Neither is broken yet. Memory saturation ends in the container being killed and restarted, losing
whatever it was processing. CPU saturation does not error — it just makes the service slower, which
shows up downstream as growing lag or backlog.

## Dashboards

- [Pulsar Overview](https://grafana-infosys-prod-dpbde9bwdscpf8b9.weu.grafana.azure.com/d/bf7ckpemufy0wa) — whether the service is actually falling behind as a result

## What to do

The alert names the pod and container. Start there, and look at the **shape** of the memory graph
over the last week — it decides what you do next.

```sh
K="kubectl"   # point kubectl at the prod cluster (dev: the dev cluster)

$K -n transitdata top pods --sort-by=memory | head -15
$K -n transitdata describe pod <pod> | grep -A6 -i "limits\|last state"
```

- **Sawtooth** (rises, drops sharply, rises again) — normal JVM garbage collection. If the peaks
  touch the limit, the limit is simply too low for this workload.
- **Steady climb over days** — a memory leak. Raising the limit buys time and hides it.
- **Sudden step change** — something changed recently. Check what was deployed.

## Likely causes

1. **The limit is too low for normal peak load** — most common. The service is fine and just needs
   more headroom.
2. **Input volume has grown** — the service was sized correctly once; check whether its input rates
   have risen before assuming the limit is wrong.
3. **A memory leak** — steady climb with no plateau.
4. **A backlog being worked through** — catching up after an outage temporarily uses more of
   everything. Resolves on its own.

## What to do next

For a limit that is too low, raise it in `manifests/<service>.yaml` in
[`transitdata-aks-deploy`](https://github.com/HSLdevcom/transitdata-aks-deploy) (`prod-deploy` /
`dev-deploy` branch). For a leak, raising the limit is a stopgap — raise a ticket against the
service. For CPU throttling, check whether anything downstream is actually suffering before acting;
a pod at its CPU limit while everything keeps up is not urgent.

## Who to contact

Team first — resource limits live in our deploy repo, so this is usually a change the team makes
itself.
