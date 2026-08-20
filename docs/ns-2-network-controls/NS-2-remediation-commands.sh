#!/usr/bin/env bash
# =============================================================================
# NS-2 "Secure cloud services with network controls" — remediation commands
# =============================================================================
# REVIEW ONLY — DO NOT RUN AS A WHOLE. Execute per resource, after reading each
# block. These commands mutate live storage accounts, key vaults and databases;
# a wrong allow-list can cut off running services.
#
# Guardrails before you run ANYTHING:
#   1. Run from a network/identity that will REMAIN allowed (or add your own IP
#      first) — enabling a firewall can lock you out of the resource.
#   2. Cross-subscription subnet rules require the subnet to have the matching
#      service endpoint (Microsoft.Storage / Microsoft.KeyVault) enabled.
#   3. Do PostgreSQL public->private in a maintenance window.
#   4. Re-run the compliance query (bottom of file) after each change.
#
# Classification rule (per HSL guidance):
#   Open data   -> allow from anywhere == Azure Policy EXEMPTION (an allow-all
#                  rule still fails "restrict network access").
#   Secret data -> allow ONLY the currently required source(s).
# =============================================================================

set -uo pipefail

# ---- Identifiers -----------------------------------------------------------
MG="572a41dd-c389-4f0a-b256-aefd1bf149d7"
ASSIGNMENT_ID="/providers/microsoft.management/managementgroups/${MG}/providers/microsoft.authorization/policyassignments/ns2_secure_cl_services"
REF_RESTRICT="14308504049673084207"   # Storage accounts should restrict network access
REF_PUBLIC="5756748729114105955"      # Storage account public access should be disallowed
REF_KV="4070969111844704992"          # Key Vault firewall / public access
REF_PG="3533816722383560650"          # PostgreSQL flexible server public access

# ---- Subscriptions ---------------------------------------------------------
SUB_TRANSITDATA="aefc968e-570c-4b24-9415-e49b9951e2ff"
SUB_KARTTA="178d6e3a-0d34-473d-b146-c1a7f372d14d"
SUB_TRANSITLOG="73da4ae2-1b25-4aab-ad39-8b759257f3a5"
SUB_DEVINFOSYS="bc21a1e6-b084-4051-b236-b1e60b3bb5c3"

# ---- Required-access sources (discovered) ----------------------------------
KART_EGRESS_IP="20.31.19.174"   # karttatuotanto-aks outbound public IP (kubenet)
INFOSYS_PROD_SUBNET="/subscriptions/87c89f8e-8790-40fc-9eb2-df634bf07208/resourceGroups/rg-aksinfosys-prod-weu/providers/Microsoft.Network/virtualNetworks/vnet-aksinfosys-prod-weu/subnets/snet-aksinfosys-prod-aks"
INFOSYS_DEV_SUBNET="/subscriptions/${SUB_DEVINFOSYS}/resourceGroups/rg-aksinfosys-dev-001/providers/Microsoft.Network/virtualNetworks/vnet-aksinfosys-dev-001/subnets/snet-aksinfosys-dev-001"
# NOTE: transitdata workloads run in the aksinfosys-PROD cluster (cross-sub).
#       Transitlog source is UNCONFIRMED — verify before applying C2.
ADMIN_IP="<YOUR.PUBLIC.IP.HERE>"    # add your own IP so you keep access

# =============================================================================
# A. OPEN DATA -> Policy exemptions (keep serving anonymously / from anywhere)
#    Verify each is genuinely open data BEFORE exempting.
# =============================================================================

# A1 transitdataprod (GTFS-RT public datasets) — exempt from both storage policies
az policy exemption create \
  --name "ns2-opendata-transitdataprod" \
  --display-name "NS-2 open-data waiver: transitdataprod" \
  --policy-assignment "$ASSIGNMENT_ID" \
  --policy-definition-reference-ids "$REF_RESTRICT" "$REF_PUBLIC" \
  --exemption-category Waiver \
  --scope "/subscriptions/${SUB_TRANSITDATA}/resourceGroups/transitdata-prod/providers/Microsoft.Storage/storageAccounts/transitdataprod" \
  --description "Open data (GTFS-RT full datasets). Anonymous public + open network access required."

# A2 transitdatadev
az policy exemption create \
  --name "ns2-opendata-transitdatadev" \
  --display-name "NS-2 open-data waiver: transitdatadev" \
  --policy-assignment "$ASSIGNMENT_ID" \
  --policy-definition-reference-ids "$REF_RESTRICT" "$REF_PUBLIC" \
  --exemption-category Waiver \
  --scope "/subscriptions/${SUB_TRANSITDATA}/resourceGroups/transitdata-dev/providers/Microsoft.Storage/storageAccounts/transitdatadev" \
  --description "Open data (GTFS-RT, dev). Anonymous public + open network access required."

# A3 ortophotos (public orthophoto tiles served to jore-map-ui)
az policy exemption create \
  --name "ns2-opendata-ortophotos" \
  --display-name "NS-2 open-data waiver: ortophotos" \
  --policy-assignment "$ASSIGNMENT_ID" \
  --policy-definition-reference-ids "$REF_RESTRICT" "$REF_PUBLIC" \
  --exemption-category Waiver \
  --scope "/subscriptions/${SUB_KARTTA}/resourceGroups/orthotiling/providers/Microsoft.Storage/storageAccounts/ortophotos" \
  --description "Open data (orthophoto tiles). Anonymous public + open network access required."

# A4 Managed infra you should NOT hand-modify -> exempt instead:
#    fc48d9d4ed91042eeb5a155 (AKS node storage, MC_ RG) and
#    csb178d6e3a0d34x473dxb14 (Cloud Shell storage). Locking these breaks the
#    cluster / Cloud Shell. Create RESTRICT-only exemptions (or delete csb if unused).
az policy exemption create \
  --name "ns2-infra-aksnode-devinfosys" \
  --display-name "NS-2 waiver: AKS-managed node storage" \
  --policy-assignment "$ASSIGNMENT_ID" \
  --policy-definition-reference-ids "$REF_RESTRICT" \
  --exemption-category Waiver \
  --scope "/subscriptions/${SUB_DEVINFOSYS}/resourceGroups/MC_rg-aksinfosys-dev-001_aks-aksinfosys-dev-001_westeurope/providers/Microsoft.Storage/storageAccounts/fc48d9d4ed91042eeb5a155" \
  --description "AKS-managed node storage (MC_ resource group) — managed by AKS, not hand-configurable."

# A5 karttatuotantocommon / karttatuotantocommoa013 — DECISION NEEDED.
#    publicBlob is already False; they only trip RESTRICT. If they serve open
#    tiles/fonts -> exempt (as A1). If internal -> restrict (as section B).

# =============================================================================
# B. INTERNAL storage -> restrict network access (only if NOT open data)
#    Example for the transitdata dev aux accounts (verify they are internal).
# =============================================================================
for ACCT in storageaccounttrans993e storageaccounttrans9918 storageaccounttrans879f; do
  az storage account update -n "$ACCT" -g transitdata-dev --subscription "$SUB_TRANSITDATA" \
    --default-action Deny --bypass AzureServices Logging Metrics
  az storage account update -n "$ACCT" -g transitdata-dev --subscription "$SUB_TRANSITDATA" \
    --allow-blob-public-access false
  # allow the cluster that uses them (verify: dev-infosys subnet shown; requires Microsoft.Storage endpoint on the subnet)
  az storage account network-rule add -n "$ACCT" -g transitdata-dev --subscription "$SUB_TRANSITDATA" \
    --subnet "$INFOSYS_DEV_SUBNET"
done

# =============================================================================
# C. SECRET data -> Key Vault firewalls (allow ONLY required source)
#    Pattern: default Deny + bypass AzureServices + one allow rule.
#    Add your ADMIN_IP first so you do not lock yourself out.
# =============================================================================

# C1 transitdata vaults (workloads run in aksinfosys-PROD -> subnet rule, cross-sub)
for KVLT in transitdata-common-vault transitdata-dev-vault transitdata-prod-vault alerts-dev-vault alerts-prod-vault; do
  az keyvault update -n "$KVLT" --subscription "$SUB_TRANSITDATA" \
    --default-action Deny --bypass AzureServices
  az keyvault network-rule add -n "$KVLT" --subscription "$SUB_TRANSITDATA" --subnet "$INFOSYS_PROD_SUBNET"
  # az keyvault network-rule add -n "$KVLT" --subscription "$SUB_TRANSITDATA" --ip-address "$ADMIN_IP"
done

# C2 Transitlog vault — SOURCE UNCONFIRMED. Discover the consumer's egress first,
#    then add the correct subnet/IP. Do not enable Deny until the allow rule is set.
az keyvault update -n transitlog-vault --subscription "$SUB_TRANSITLOG" --default-action Deny --bypass AzureServices
# az keyvault network-rule add -n transitlog-vault --subscription "$SUB_TRANSITLOG" --ip-address "<transitlog-consumer-egress>"

# C3 karttatuotanto vaults (karttatuotanto-aks is kubenet -> egress IP rule)
for KVLT in karttatuotanto-keyvault karttatuotanto-vault kartat-aks-vault kartat-aks-vault-dev karttatuotanto-tsp-vault orthotiling-keyvault; do
  RG=$(az keyvault show -n "$KVLT" --subscription "$SUB_KARTTA" --query "resourceGroup" -o tsv)
  az keyvault update -n "$KVLT" --subscription "$SUB_KARTTA" --default-action Deny --bypass AzureServices
  az keyvault network-rule add -n "$KVLT" --subscription "$SUB_KARTTA" --ip-address "$KART_EGRESS_IP"
done

# =============================================================================
# D. PostgreSQL flexible servers (karttatuotanto) -> disable public access
#    The compliant target is private access (VNet integration / private endpoint).
#    RISK: toggling public->private can require reconfiguration and downtime.
#    Interim: restrict firewall to the app egress, then plan private endpoint.
# =============================================================================
# Interim firewall (keeps public on, but narrows it — still non-compliant, use as bridge):
az postgres flexible-server firewall-rule create \
  -g karttatuotanto-prod -n karttatuotanto-prod-postgres-map-data \
  --rule-name allow-karttatuotanto-aks --start-ip-address "$KART_EGRESS_IP" --end-ip-address "$KART_EGRESS_IP"
# Compliant target (verify exact flag for your CLI version; do in a maintenance window):
# az postgres flexible-server update -g karttatuotanto-prod -n karttatuotanto-prod-postgres-map-data --public-network-access Disabled
# az postgres flexible-server update -g karttatuotanto-dev  -n karttatuotanto-dev-postgres-map-data  --public-network-access Disabled

# =============================================================================
# E. Validation — re-run after each change
# =============================================================================
# az policy state list --subscription "$SUB_TRANSITDATA" \
#   --filter "PolicyAssignmentName eq 'ns2_secure_cl_services' and ComplianceState eq 'NonCompliant'" \
#   --query "[].{ref:policyDefinitionReferenceId, res:resourceId}" -o tsv | sort -u
