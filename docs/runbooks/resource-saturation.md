# Runbook: resource saturation and mis-sizing

Covers the alerts in the `transitdata-capacity-{dev,prod}` rule group, plus `HighMemoryUsage`
and `HighCPUUsage` in `transitdata-infra-{dev,prod}`.

All of them say the same kind of thing: **a number in a manifest no longer matches what the
workload actually does.** None of them means the service is down — `PodCrashLooping`,
`PodNotReady` and `ContainerOOMKilled` cover that, and those rules annotate a
`docs/runbooks/pod-health.md` that has never been written. Writing it is a separate,
outstanding piece of work.

## First: is this one workload or the whole fleet?

Open **Kubernetes / Compute Resources / Pod** in Grafana (linked from the alert) and set the
namespace and pod from the alert labels. Everything below is visible on that one dashboard.

If several unrelated workloads alert at once, suspect the node rather than the workloads —
check node pressure and recent scaling before touching any manifest.

## The alerts

### `ContainerCpuThrottled` — usage is being capped

More than 25% of the container's CPU periods ended with it stopped at its limit, for 20
minutes.

This is the one that costs pipeline latency without showing up as an error anywhere. CFS
enforces the limit per 100ms period, so a container averaging well under its limit can still
be stopped for a quarter of every period and take four times as long to do its work.

**Do:** raise the **limit**, not the request. Roughly `1.25 x` the p95 usage; the sizing tool
computes exactly that. Re-check after a day — if throttling persists, the workload wants more
than its p95 suggests and the p95 was itself measured under throttling.

**Do not** try to fix it by lowering the request, and do not size a throttled workload from
its own measurements without raising the limit first: every CPU statistic it produces is
censored by the limit you are trying to set.

### `ContainerCpuRequestTooLow` / `ContainerMemoryRequestTooLow` — the scheduler is misinformed

Sustained usage above 1.5x the CPU request, or 1.25x the memory request.

Requests are what the scheduler packs nodes with, and what guarantees a share once a node is
busy. A container above its request is being subsidised by whatever else landed on the same
node, and the bill arrives as *that* workload's throttling. For memory it is worse: the pod is
first in line to be evicted when the node comes under pressure.

**Do:** re-run the sizing tool and apply the new request. This is the routine case.

### `ContainerCpuOverAllocated` / `ContainerMemoryOverAllocated` — paying for nothing

Peak usage stayed under 25% of the CPU request, or 40% of the memory request, for 24 hours.

Requests are reserved outright, so this is capacity no other workload can use.

**Do:** re-run the sizing tool. **Check `overrides.yaml` before lowering anything** — some
floors there are startup budget rather than steady-state headroom, and the alert cannot tell
the difference. A JVM service can idle at 200m and still need a core to finish class loading
inside its startup probe window.

**Do not** treat a single alert as urgent. This is review material, batched with the next
sizing pass.

### `ContainerMissingResourceLimits` — nothing is bounding this container

No memory limit at all. Nothing stops it taking the whole node, and every pod scheduled beside
it is at its mercy. It is also invisible to every other alert here, which all compare against
a limit.

**Do:** add a `resources` block to the manifest. The sizing tool reports a recommendation but
deliberately will not create the block — what a workload should be *allowed* to do is a
decision, not a measurement.

### `HighMemoryUsage` — 90% of the memory limit

The warning before an OOM kill. Either the limit is too low or the workload is leaking.

**Do:** check whether the working set is flat-but-high or still climbing. Flat and high means
the limit is simply too low; raise it. Still climbing over hours or days is a leak, and
raising the limit only buys time — it belongs in the service's own backlog.

### `HighCPUUsage` — 90% of the CPU limit

Largely superseded by `ContainerCpuThrottled`, which measures the consequence rather than the
proxy, and worth retiring once the capacity rules have proven themselves. A container can sit at 60% of its limit on average and still be badly throttled. Treat
a `HighCPUUsage` alert with no matching throttle alert as informational.

## The standard remediation

```sh
cd tools/rightsize
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt

.venv/bin/python rightsize.py --env prod            # report only
```

Read `reports/<env>-<date>.md`, then check out the right deploy branch and re-run with
`--apply`. Environments are separated by branch, not by directory, and `--apply` refuses to
run on the wrong one.

Two things the tool will not do on its own, both by design:

- It holds back any limit that would fall by more than 75%, and reports it instead. If the cut
  is right, record why in `overrides.yaml` and re-run; if it is not, the floor belongs there
  anyway.
- It refuses to change a memory limit on a container that pins an absolute heap size
  (`--max-old-space-size`, `-Xmx`), because moving one without the other either wastes the
  headroom or puts the heap ceiling above the cgroup limit. Change both together.

Full documentation: `tools/rightsize/README.md` in `transitdata-aks-deploy` and
`transitlog-aks-workload`.

## When an alert is wrong

Thresholds here are starting points, not findings. If a rule fires repeatedly on a workload
that is genuinely fine, change the rule rather than muting it — `alerts/capacity.bicep` in
`transitdata-aks-deploy`, then `./deploy.sh <env>` to see the diff before applying it. An
alert nobody acts on is worse than no alert, because it teaches people to skip the channel.
