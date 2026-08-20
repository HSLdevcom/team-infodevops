# NS-2 "Secure cloud services with network controls" — Implementation Tasks

*Azure DevOps backlog · Enforcement (deny-all) date: **2026-05-18** · Based on the `az policy state` compliance inventory ([HSL_NS-2_network_controls_compliance.xlsx](./HSL_NS-2_network_controls_compliance.xlsx)). Exact commands: [NS-2-remediation-commands.sh](./NS-2-remediation-commands.sh).*

Hierarchy: **Epic → Features → Tasks**. Each **Task** = one Azure DevOps ticket. Classification drives the fix: **[OPEN]** = policy exemption (open data, allow from anywhere); **[SECRET]** = allow only the required source; **[INFRA]** = managed infra, exempt; **[DB]** = disable public / go private. **[verify]** = confirm classification or the required source before acting.

## Epic: Bring HSL subscriptions into NS-2 network-controls compliance

---

### Feature A — Prerequisites: access & classification

- **A1 — Obtain policy-read access to the blocked subscriptions.** `AuthorizationFailed` on PolicyInsights for **HSL Storage**, **HSLAZ-CORP-TEST-INFOSYS**, **HSLAZ-PLATFORM-PROD-CONNECTIVITY**, **HSLAZ-PLATFORM-PROD-MANAGEMENT**. HSL Storage is the priority — it holds `hfpv2` + `hslstoragekarttatuotanto` (our main open data). *Done when:* Resource Policy Reader/Contributor granted and inventory re-run.
- **A2 — [verify] Confirm open-data classification.** For `transitdataprod`, `transitdatadev`, `karttatuotantocommon`, `karttatuotantocommoa013`: confirm they serve open data anonymously (vs. hold any internal data) before exempting. *Done when:* each is labelled OPEN or SECRET with justification.
- **A3 — [verify] Discover required source for `transitlog-vault`.** No AKS cluster in the Transitlog subscription; identify which workload/egress consumes it. *Done when:* the allow-list source (subnet or IP) is known.

### Feature B — Open-data exemptions

- **B1 — [OPEN] Exempt `transitdataprod`** from `RESTRICT` + `PUBLIC` (GTFS-RT public datasets).
- **B2 — [OPEN] Exempt `transitdatadev`** from `RESTRICT` + `PUBLIC`.
- **B3 — [OPEN] Exempt `ortophotos`** from `RESTRICT` + `PUBLIC` (public orthophoto tiles).
- **B4 — [INFRA] Exempt `fc48…` (AKS node storage, dev-infosys)** from `RESTRICT` — AKS-managed, not hand-configurable.
- **B5 — [INFRA] Exempt or delete `csb…` Cloud Shell storage** (karttatuotanto) — locking it breaks Cloud Shell; delete if unused.
- **B6 — [OPEN/verify] Decide `karttatuotantocommon` + `…commoa013`.** If open tiles/fonts → exempt (`RESTRICT` only, publicBlob already false); if internal → move to Feature C-style restrict.

### Feature C — Key Vault firewalls (secret data → allow only required source)

- **C1 — [SECRET] transitdata: 5 vaults** (`transitdata-common/dev/prod-vault`, `alerts-dev/prod-vault`) → default Deny + bypass AzureServices + allow `snet-aksinfosys-prod-aks` (cross-sub; needs `Microsoft.KeyVault` service endpoint on the subnet).
- **C2 — [SECRET][verify] Transitlog: `transitlog-vault`** → default Deny + allow the source from A3.
- **C3 — [SECRET] karttatuotanto: 6 vaults** (`karttatuotanto-keyvault`, `karttatuotanto-vault`, `kartat-aks-vault`, `kartat-aks-vault-dev`, `karttatuotanto-tsp-vault`, `orthotiling-keyvault`) → default Deny + allow egress IP `20.31.19.174`.

### Feature D — PostgreSQL flexible servers (karttatuotanto)

- **D1 — [DB] `karttatuotanto-dev-postgres-map-data`** → disable public network access; VNet integration / private endpoint. Interim: firewall to `20.31.19.174`.
- **D2 — [DB] `karttatuotanto-prod-postgres-map-data`** → same, in a maintenance window (production).

### Feature E — Validation & guardrails (cross-cutting)

- **E1 — Pre-change access safeguard.** Before enabling any firewall, ensure the operator's IP/identity stays allowed (add `ADMIN_IP`) to avoid lock-out.
- **E2 — Post-change compliance re-check.** After each resource, re-run `az policy state list` for the assignment; confirm the resource drops off the non-compliant list.
- **E3 — Service-health verification.** After enforcement, confirm no service regressions (GTFS-RT feeds, map tiles, AKS secret mounts, DB connectivity). Enforcement date has passed per current date — check whether anything already broke.

---

### Dependencies
- **A1/A2/A3 gate** B6, C1, C2 (classification + source must be known first).
- **E1 precedes** every C and D task (lock-out risk).
- **D1/D2** need a private-networking design decision (VNet integration vs private endpoint) before execution.

### Rollout note
No changes have been applied. Sequence per subscription, dev before prod, one resource at a time, re-checking compliance (E2) and service health (E3) between changes.
