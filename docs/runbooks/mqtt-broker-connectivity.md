# MQTT broker connection problem

| Alert | Meaning |
|---|---|
| `MqttBrokerDisconnected` | We are not connected to a broker |
| `MqttHfpRedundantPairBothDown` | Both HFP brokers are down — vehicle positions stop network-wide |
| `MqttConnectionUnstable` | The connection keeps dropping and reconnecting |

If a broker is connected but sending nothing, that is a different problem — see
[mqtt-no-messages](./mqtt-no-messages.md).

## What it means

`MqttBrokerDisconnected` reports the **monitoring** connection. The pipeline gateways connect
separately, so this can fire while ingestion continues normally — check the message rates before
assuming an outage. Still worth fixing, because a lost monitoring connection leaves us blind.

`MqttHfpRedundantPairBothDown` is always serious: those two brokers carry the same vehicle-position
firehose for the whole network. One down is tolerable; both down means buses, trams and metro
disappear from Reittiopas and stop displays.

## Dashboards

- [MQTT message counts](https://grafana-infosys-prod-dpbde9bwdscpf8b9.weu.grafana.azure.com/d/mqtt-message-counts-prod) — if rates for that broker are normal, only the monitoring connection dropped and nothing is being lost

## What to do

```sh
kubectl -n transitdata logs \
  -l app=transitdata-metrics-exporter --tail=100 | grep -i -E "connect|disconnect|error"
```

The log records each connect and disconnect with the broker address — the quickest way to tell a
broker refusing us from a network problem on our side.

## Likely causes

1. **Broker restart or maintenance** — usually brief and self-healing. If it cleared before you
   looked, this was it.
2. **Our egress IP is not allowlisted** — several brokers restrict by IP, so a NAT gateway change
   breaks all of them at once. The exporter log says so explicitly.
3. **Duplicate client ID** — two clients using the same MQTT client ID repeatedly knock each other
   off. This is the classic cause of `MqttConnectionUnstable`; look for a second client using the
   same ID (often a recently duplicated deployment) before anything else.
4. **The exporter pod is restarting** — see [metrics-exporter-down](./metrics-exporter-down.md).

## What to do next

Most of these are not fixed from our side. Confirm whether it is us or them from the exporter log,
then either fix the allowlist / client ID, or contact the broker owner.

## Who to contact

Team first. Broker-side problems belong to the owner of that specific broker — the prod GTFS-RT
output broker `predin.rt.hsl.fi` is **Contrasec**; HFP and APC input brokers are HSL-operated. An
egress/NAT change is the platform team (`azure-infra-aks` owners).
