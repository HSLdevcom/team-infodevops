# MQTT feed has gone silent

| Alert | Meaning |
|---|---|
| `ServiceAlertsFeedSilent`, `FullApcFeedSilent`, `MetroHfpFeedSilent`, `MqttFeedSilent`, `MqttNightlyFeedSilent` | We are connected to the broker, but no messages are arriving on a feed |

The connection is fine, so the problem is **upstream of us** — the publisher has stopped sending.
(If the connection itself dropped, see [mqtt-broker-connectivity](./mqtt-broker-connectivity.md).)
The alert names the broker and topic.

## What it means

| Feed | Consequence |
|---|---|
| Service alerts (`gtfsrt/v2/fi/hsl/sa`) | Disruption info stops reaching passengers — apps show no disruptions even when there are some |
| Metro vehicle positions | Metro disappears from Reittiopas and stop displays |
| HFP firehose (`hfprec938` / `939`) | Vehicle positions for the whole network |
| Full APC | Passenger counting stops. Not passenger-visible, but the gap is permanent — this data is never replayed |
| EKE, metro-mipro, ferry | Narrower impact; check with the feed owner |

## Dashboards

- [MQTT message counts](https://grafana-infosys-prod-dpbde9bwdscpf8b9.weu.grafana.azure.com/d/mqtt-message-counts-prod) — per-feed panels. If **all** feeds go quiet at once, it is the exporter, not the brokers → [metrics-exporter-down](./metrics-exporter-down.md).

## Is this normal?

Some feeds legitimately stop overnight — metro stops running around 00:20 and resumes around 04:40
(later on Sunday mornings), and the Suomenlinna ferry and metro-mipro schedule feeds also go quiet
for a few hours. A metro or ferry alert in the middle of the night is usually normal.

`MqttNightlyFeedSilent` already allows for the normal night gap, so if that one fired the feed has
been silent well beyond what it normally does, whatever the hour.

## Likely causes

1. **The upstream publisher has stopped** — the case this alert exists for. Our side is healthy and
   nothing is being sent.
2. **Scheduled silence** — metro or ferry at night, as above.
3. **Topic filter no longer matches** — the subscription succeeds but no messages ever arrive.
   Suspect this after any change to broker or topic configuration; the filters are in
   `manifests/transitdata-metrics-exporter.yaml` in
   [`transitdata-aks-deploy`](https://github.com/HSLdevcom/transitdata-aks-deploy).
4. **The broker accepted the connection but is not delivering** — rare.

## What to do

Little of this is fixable from our side. Confirm the feed is genuinely down (the dashboard, or a
second consumer, is the quickest cross-check), then contact the feed owner. **Note the start
time** — the gap is not recoverable and downstream consumers will ask.

## Who to contact

Team first, then the owner of the specific upstream feed. For service alerts / trip updates on the
prod output broker `predin.rt.hsl.fi`, that is **Contrasec**. HFP and APC input brokers are
HSL-operated.
