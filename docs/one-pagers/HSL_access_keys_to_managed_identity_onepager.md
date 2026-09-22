# Retiring Storage Access Keys in HSL Services

**Moving to Managed Identity + RBAC · One-pager**

*HSL · Internal · Based on the 2026-07 access-key audit ([HSL_access_key_inventory.xlsx](../../../HSL_access_key_inventory.xlsx))*

---

## What?

Replace long-lived Azure **Storage account access keys** — and everything derived from them (key-based connection strings and account SAS) — across HSL services with **Microsoft Entra ID authentication via Managed Identities + RBAC**, then disable shared-key access on the storage accounts.

Scope (from the audit): ~20 services and ~10 storage accounts — `transitdata`, `hfpv2`, `eke`, the `karttatuotanto` family, `ortophotos`. Keys are typically stored in Key Vault, injected as env vars, and assembled into connection strings at runtime. Five concrete patterns to replace:

| Current pattern | Where it appears (from audit) | Replace with |
|---|---|---|
| Connection string with `AccountKey` (`DefaultEndpointsProtocol=…;AccountKey=…`) | gtfsrt-full-publisher (`AzureSink.java`); EKE sinks & ekecheck (`BLOBSTORAGE_ENDPOINT`); HFP consumers (`HFP_STORAGE_CONNECTION_STRING`) | `DefaultAzureCredential` + account URL + RBAC data role |
| `StorageSharedKeyCredential` / `AZURE_STORAGE_KEY` (Node) | hsl-map-publisher, hsl-routemap-server, jore-graphql-import, jore-history-graphql-import, osm2vectortiles-monitor | `@azure/identity` `DefaultAzureCredential` + RBAC |
| Key stored as Key Vault secret, injected as env var | `transitdata-azure-storage-key`, kartat-aks-vault `azure-storage-key`, `eke-blobstorage-endpoint` | Delete secret; grant workload identity a data-plane role directly |
| Account SAS URL (key-signed) | `azure-fonts-sas-url` (kartat-aks-vault) | User-delegation SAS (Entra-signed) or direct MI access |
| Anonymous public blob / `$web` static host | `hslstoragekarttatuotanto` (`$web`), `ortophotos` (public read) | Not a key — review whether public access is intended |

## Why?

- **Security.** An access key grants full, non-expiring, unscoped control of the whole account, with no per-identity audit. Rotating one breaks every consumer at once, so rotation rarely happens. The audit found key/connection-string material spread across ~20 repos, including committed `.env` files. Managed identity means no stored secret, short-lived auto-rotated tokens, least-privilege per container, per-identity logs, and central revocation.
- **Operational.** Removes the vault → env-var → connection-string plumbing and the rotation-coordination problem. The audit showed the cost directly: firewalled/permission-blocked vaults, scattered key copies, and an orphaned reference (`feedbackfiles`).
- **Strategic.** Microsoft recommends disabling shared-key auth; it aligns with HSL's standardization drive (shared workflows, base images). The AKS clusters already run a managed identity for the Key Vault CSI driver (`useVMManagedIdentity=true`) — the same identity can be granted Storage roles, so much of the groundwork exists.

## How?

1. **Inventory & classify** — done (see `HSL_access_key_inventory.xlsx`). Tag each consumer as reader or writer.
2. **Establish workload identities** — AKS Workload Identity (or the existing kubelet MI) per workload; system-assigned MI for Functions; MI for VMs.
3. **Assign least-privilege RBAC** — scope data-plane roles to the account or container:

   | Workload class | RBAC role | Services |
   |---|---|---|
   | Writers (upload/archive) | Storage Blob Data Contributor | gtfsrt-full-publisher, eke-sink, hfp/csv/split sinks, apc-archive-sink, map-publisher, routemap-server, jore(-history)-graphql-import |
   | Readers (import/monitor) | Storage Blob Data Reader | hfp-analytics, hfp-loader, toimivuus, hfp-csv-sink-monitor, ekecheck, osm2vectortiles-monitor |
   | Key Vault reads | Key Vault Secrets User | Move access-policy vaults to RBAC authorization (AKS CSI already uses a managed identity) |

4. **Update code to `DefaultAzureCredential`** — swap connection strings/keys for an account URL + credential. Java: `DefaultAzureCredentialBuilder`; Python: `azure-identity`; Node: `@azure/identity`. Local dev keeps working via `az login`.
5. **Cut over per service** (dev → test → prod) and verify with the storage account's Transactions metric split by **Authentication = 0 shared-key**.
6. **Enforce & clean up** — set `allowSharedKeyAccess=false`, delete the key secrets from Key Vault, and retire the old keys. Replace account SAS with user-delegation SAS; review anonymous public containers.
7. **Track exceptions** — resolve `feedbackfiles` (referenced but not found) first; handle JORE4 (`stjore4*` / `kv-jore4-*`) separately, as it lives in a subscription not currently accessible.

---

## Implementation Tasks (Azure DevOps backlog)

The list below is structured as a ready-to-import work-item hierarchy: **Epic → Features → Tasks**. Each **Task** is intended to become one Azure DevOps ticket. Storage-account cutover is grouped per account because `allowSharedKeyAccess=false` can only be set once *every* consumer of that account is off keys. Each code-change task is tagged **[W]** (writer → *Storage Blob Data Contributor*) or **[R]** (reader → *Storage Blob Data Reader*); **[verify]** means the read/write classification must be confirmed from the code before assigning the role.

### Epic: Eliminate Storage Account access keys — migrate HSL services to Managed Identity + RBAC

---

#### Feature 0 — Foundation & platform enablement

- **T0.1 — Enable Workload Identity on AKS clusters.** Enable Entra Workload Identity (OIDC issuer + federated credentials) on the transitdata, transitlog and karttatuotanto AKS clusters, or confirm the existing kubelet/VM managed identity can be reused. *Done when:* a workload can obtain a token via `DefaultAzureCredential` with no secret mounted.
- **T0.2 — Provision managed identities for non-AKS workloads.** System-assigned MI for any Azure Functions (e.g. `hfp-analytics`) and MI for VMs (`orthotiling`). *Done when:* each non-AKS consumer has an MI.
- **T0.3 — Define RBAC role-assignment convention + IaC.** Standardize how Storage Blob Data roles are scoped (per account vs per container) and codify assignments as IaC so they are reproducible. *Done when:* a documented pattern + template exists.
- **T0.4 — Create shared `DefaultAzureCredential` helpers.** Java helper (host in `transitdata-common`), plus reference snippets for Node (`@azure/identity`) and Python (`azure-identity`), incl. local-dev via `az login`. *Done when:* helpers published and referenced by at least one migrated service.

#### Feature 1 — Key Vault authorization & access unblocking

- **T1.1 — Migrate access-policy vaults to Azure RBAC authorization** and grant workloads **Key Vault Secrets User** (transitlog-vault, transitdata-*-vault, karttatuotanto-*-vault).
- **T1.2 — Unblock audit/enumeration access.** Add operator IP/VPN allowlist for firewalled vaults (`kv-aksinfosys-*`, `kv-joremap-*`) and grant `Microsoft.Storage/…/listKeys` (Storage Account Key Operator) on `eke`, `satfstatedbdev001`, `satfstatedbprod001` so the remaining keys can be verified/rotated.

#### Feature 2 — Account cutover: `transitdataprod` / `transitdatadev` (+ aux trans993e/879f/9918)

- **T2.1 — Grant RBAC** to the gtfsrt-full-publisher workload identity on the transitdata storage accounts (prod + dev).
- **T2.2 — [W] Migrate `transitdata-gtfsrt-full-publisher`** (`AzureSink.java`) from `AccountName`/`AccountKey` connection string to `DefaultAzureCredential` + account URL. Covers servicealert / vehicleposition / tripupdate deployments.
- **T2.3 — Remove `transitdata-azure-storage-key(-dev)`** from `kv-aksinfosys-prod-weu` and the `TRANSITDATA_AZURE_STORAGE_KEY*` env wiring in `transitdata-aks-deploy`.

#### Feature 3 — Account cutover: `hfpv2` (HFP + APC blob store)

- **T3.1 — Grant RBAC** to all hfpv2 consumer identities (readers vs writers).
- **T3.2 — [W] Migrate `transitlog-hfp-sink`** to MI (HFP write path).
- **T3.3 — [W] Migrate `transitlog-apc-archive-sink`** (`BLOB_ACCOUNT_NAME`/`BLOB_CONTAINER`).
- **T3.4 — [R] Migrate `hfp-analytics`** importer (`HFP_STORAGE_CONNECTION_STRING`).
- **T3.5 — [R] Migrate `hfp-loader`** (`utils/azureStorage.ts`). **[verify]**
- **T3.6 — [R] Migrate `toimivuus`** (`toimivuus/hfp_import.py`).
- **T3.7 — [R] Migrate `transitlog-hfp-csv-sink-monitor`** (`HFP_STORAGE_ACCOUNT_NAME`).
- **T3.8 — Remove the HFP connection-string secret** and `HFP_STORAGE_CONNECTION_STRING` wiring once all above are cut over.

#### Feature 4 — Account cutover: `eke` (EKE data-warehouse store)

- **T4.1 — Grant RBAC** to the EKE consumer identities (depends on T1.2 to reach the account).
- **T4.2 — [W] Migrate `transitdata-eke-sink`** (`BLOBSTORAGE_ENDPOINT`).
- **T4.3 — [W] Migrate `transitlog-hfp-split-sink`**.
- **T4.4 — [W] Migrate `transitlog-hfp-csv-sink`** (`eke-csv`).
- **T4.5 — [R] Migrate `transitlog-ekecheck`**.
- **T4.6 — Remove `eke-blobstorage-endpoint`** secret from `kv-aksinfosys-prod-weu`.

#### Feature 5 — Account cutover: karttatuotanto family (`hslstoragekarttatuotanto`, `karttatuotantocommon`)

- **T5.1 — Grant RBAC** to the karttatuotanto consumer identities.
- **T5.2 — [W] Migrate `hsl-map-publisher`** (`cloudService.js`, `AZURE_STORAGE_KEY`).
- **T5.3 — [W] Migrate `hsl-routemap-server`** (`cloudService.js`, `routemap-prod`).
- **T5.4 — [W] Migrate `jore-graphql-import`** (`StorageSharedKeyCredential`, DB-dump upload).
- **T5.5 — [W] Migrate `jore-history-graphql-import`** (DB-dump upload).
- **T5.6 — [R] Migrate `osm2vectortiles-monitor`** (`AZURE_TILES_CONTAINER`).
- **T5.7 — [verify] Migrate `hsl-jore-postgis`** (`init.sh`, `AZURE_STORAGE_KEY`) — confirm usage first.
- **T5.8 — Remove `azure-storage-key`/`azure-storage-account`** secrets from `kartat-aks-vault` (+ `-dev`) once consumers are cut over.

#### Feature 6 — SAS & public-access review

- **T6.1 — Replace account SAS `azure-fonts-sas-url`** with a user-delegation SAS (Entra-signed) or direct MI access.
- **T6.2 — Review anonymous/public access** on `hslstoragekarttatuotanto` (`$web`) and `ortophotos` (`hsl-map-style`, `hsl-map-server`, `jore-map-ui`) — confirm public read is intended; no key change required.

#### Feature 7 — Exceptions & investigations (spikes)

- **T7.1 — Locate the `feedbackfiles` storage account.** Referenced by `transitlog-server` + `transitlog-ui` but not found in any accessible subscription. Determine subscription/tenant or confirm the code is stale.
- **T7.2 — Confirm where IaC lives** (Azure DevOps vs GitHub). Org-wide code search returned 0 `Bicep/Terraform/ARM` hits — audit that layer separately for key definitions.
- **T7.3 — Request access to the JORE4 subscription** and re-run the storage-key + vault enumeration for `stjore4*` / `kv-jore4-*` (out of reach today).
- **T7.4 — Decide Terraform-state storage strategy** for `satfstatedb*` — migrate the backend to OIDC/Entra auth or keep as an accepted key-based exception.

#### Feature 8 — Enforcement & decommission (per account, gated on its Feature above)

- **T8.1 — Verify zero shared-key usage.** For each migrated account, confirm the Transactions metric split by **Authentication** shows 0 `Account key` for a full retention window.
- **T8.2 — Disable shared-key access.** Set `allowSharedKeyAccess=false` on each fully-migrated account (transitdata, hfpv2, eke, karttatuotanto family).
- **T8.3 — Rotate/retire the old keys** and delete any remaining copies from Key Vault, `.env` files and repo history.

