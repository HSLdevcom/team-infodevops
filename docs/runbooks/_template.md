# `<Short title of the problem>`

| Alert | Meaning |
|---|---|
| `<AlertName>` | `<one line — what fired>` |

## What it means

`<The user-visible consequence. Which feed or system, who is affected, how badly. If the answer is
"nothing yet, but it will soon", say that.>`

## Dashboards

- `<name>`: `<direct Grafana link, including ?viewPanel=N where useful>`

## Is this normal?

`<Only if relevant — e.g. a feed that stops overnight. Delete this section otherwise.>`

## Likely causes

Most common first.

1. **`<cause>`** — `<how to tell>`
2. **`<cause>`** — `<how to tell>`

## What to do

```sh
K="kubectl --context aks-aksinfosys-prod-weu-tunnel"   # dev: aks-aksinfosys-dev-001-tunnel

$K -n transitdata <...>
```

`<What to expect afterwards, and roughly how long recovery takes.>`

## Who to contact

`<Team first. Name the broker owner, data-source owner or platform team where the fix is not ours.>`
