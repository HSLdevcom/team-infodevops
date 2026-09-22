# Pod is unhealthy

| Alert | Meaning |
|---|---|
| `PodCrashLooping` | A pod keeps restarting instead of recovering |
| `PodNotReady` | A pod is stuck outside a Running state |
| `ContainerOOMKilled` | A container ran out of memory and was killed |

The alert names the pod. Whatever it does in the pipeline is effectively down while this lasts.

## Dashboards

- [Pulsar Overview](https://grafana-infosys-prod-dpbde9bwdscpf8b9.weu.grafana.azure.com/d/bf7ckpemufy0wa) — after recovery, check whether a backlog built up while the pod was down and is draining

## What to do

```sh
K="kubectl --context aks-aksinfosys-prod-weu-tunnel"   # dev: aks-aksinfosys-dev-001-tunnel

# what state is it actually in
$K -n transitdata get pod <pod>

# why it died — the events at the bottom are usually the answer
$K -n transitdata describe pod <pod> | tail -40

# the log of the instance that CRASHED, not the one running now
$K -n transitdata logs <pod> --previous --tail=100
```

`--previous` is the important flag — without it you are reading the fresh container's log, which by
definition has not failed yet. In `describe pod`, look at **Last State**: `OOMKilled` means memory;
`Error` with an exit code means the process itself failed; `Pending` with no Last State means it
never started.

## Likely causes

1. **Out of memory** (`Last State: OOMKilled`) — the most common cause. See
   [resource-saturation](./resource-saturation.md); restarting only buys time.
2. **A dependency is unavailable at startup** — Pulsar, Redis or a database not accepting
   connections. The pod restarts in a loop until the dependency returns, so check whether the
   dependency is the real problem before touching this pod.
3. **Bad configuration or a missing secret** — fails immediately every time, and the log says so.
   Usually follows a recent deployment; roll it back in
   [`transitdata-aks-deploy`](https://github.com/HSLdevcom/transitdata-aks-deploy).
4. **Cannot be scheduled** — stuck `Pending`; the events in `describe pod` explain why, usually no
   node with enough free resource.
5. **Node problem** — if several unrelated pods are affected at once, look at the nodes.

## What to do next

If a dependency is down, fix that and the pod recovers on its own — do not restart it in a loop. If
it is a bad config or image, roll back the deployment. If it is memory, follow
[resource-saturation](./resource-saturation.md).

## Who to contact

Team first — these are workload problems. If pods cannot be scheduled at all, or a node pool is
unhealthy, that is the platform team (`azure-infra-aks` owners).
