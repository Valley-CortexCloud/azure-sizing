#!/bin/bash

# --- Cortex Cloud Sizing (Azure Native - Multi-Sub Audit) ---
# Purpose: Deep audit of Cloud Workloads using fast Azure Resource Graph queries

# 0. Self-Healing: Install required Azure Extensions silently
az config set extension.use_dynamic_install=yes_without_prompt 2>/dev/null
if ! az extension show --name resource-graph &>/dev/null; then
    echo "Initializing Azure Resource Graph..."
    az extension add --name resource-graph &>/dev/null
fi

clear
echo "=================================================="
echo "   CORTEX CLOUD - AZURE WORKLOAD SIZING TOOL"
echo "=================================================="

# 1. SCOPE VALIDATION
echo ""
echo "PHASE 1: SCOPE VALIDATION"
echo "--------------------------------------------------"

# Get list of ALL active subscriptions (Name and ID)
TEMP_SUB_LIST=$(mktemp)
az account list --query "[?state=='Enabled'].{Name:name, Id:id}" -o tsv > "$TEMP_SUB_LIST"

SUB_COUNT=$(wc -l < "$TEMP_SUB_LIST")

while IFS=$'\t' read -r name id; do
    echo "  [✓] Found: $name ($id)"
done < "$TEMP_SUB_LIST"

ALL_SUBS_IDS=$(cut -f2 "$TEMP_SUB_LIST" | tr '\n' ' ')
rm "$TEMP_SUB_LIST"

if [[ $SUB_COUNT -eq 0 ]]; then
    echo "Error: No active subscriptions found."
    exit 1
fi

echo "--------------------------------------------------"
echo "  >> TARGETING SCOPE: $SUB_COUNT SUBSCRIPTIONS"
echo "--------------------------------------------------"
echo ""
echo "PHASE 2: ANALYZING RESOURCES..."

# HELPER FUNCTION: Runs query and ensures 0 is returned if empty
run_query() {
    local query="$1"
    local result=$(az graph query -q "$query" --subscriptions $ALL_SUBS_IDS --query "data[0].Val" -o tsv 2>/dev/null)
    
    if [[ -z "$result" || "$result" == "None" ]]; then
        echo "0"
    else
        # Remove any decimal points if returned by sum()
        printf "%.0f" "$result"
    fi
}

# 2. Run Queries (Scoped to all subscriptions)

# VMs (All instances)
VM_COUNT=$(run_query "Resources | where type =~ 'Microsoft.Compute/virtualMachines' | summarize Val=count()")

# AKS Nodes (Robust query parsing agentPoolProfiles directly)
AKS_NODES=$(run_query "Resources | where type =~ 'Microsoft.ContainerService/managedClusters' | mv-expand pool=properties.agentPoolProfiles | summarize Val=sum(toint(pool.count))")

# Function Apps (Serverless)
FUNC_APPS=$(run_query "Resources | where type =~ 'Microsoft.Web/sites' and kind contains 'function' | summarize Val=count()")

# CaaS (Container Instances & Container Apps)
CAAS_COUNT=$(run_query "Resources | where type in~ ('Microsoft.ContainerInstance/containerGroups', 'Microsoft.App/containerApps') | summarize Val=count()")

# PaaS Databases
SQL_SERVERS=$(run_query "Resources | where type =~ 'Microsoft.Sql/servers' | summarize Val=count()")
SQL_MI=$(run_query "Resources | where type =~ 'Microsoft.Sql/managedInstances' | summarize Val=count()")
COSMOS_DBS=$(run_query "Resources | where type =~ 'Microsoft.DocumentDB/databaseAccounts' | summarize Val=count()")

# Open Source Databases (Postgres, MySQL, MariaDB - Single & Flex)
OS_DBS=$(run_query "Resources | where type in~ ('Microsoft.DBforPostgreSQL/servers', 'Microsoft.DBforPostgreSQL/flexibleServers', 'Microsoft.DBforMySQL/servers', 'Microsoft.DBforMySQL/flexibleServers', 'Microsoft.DBforMariaDB/servers') | summarize Val=count()")

TOTAL_PAAS_DBS=$(( SQL_SERVERS + SQL_MI + COSMOS_DBS + OS_DBS ))

# Storage Accounts
STORAGE_ACCS=$(run_query "Resources | where type =~ 'Microsoft.Storage/storageAccounts' | summarize Val=count()")

# Container Registries (Note: ARG counts registries, not individual images)
ACR_COUNT=$(run_query "Resources | where type =~ 'Microsoft.ContainerRegistry/registries' | summarize Val=count()")

# 3. Calculate Credits
# Logic: (Count + UnitSize - 1) / UnitSize performs ceiling division

# C1: Data/Storage (Storage /10, DBs /2)
C1_STORAGE=$(( (STORAGE_ACCS + 9) / 10 ))
C1_DB=$(( (TOTAL_PAAS_DBS + 1) / 2 ))
TOTAL_C1=$(( C1_STORAGE + C1_DB ))

# C3: Compute (VMs /1, Serverless /25, CaaS /10, AKS Nodes /1, ACRs /1)
C3_VM=$(( VM_COUNT ))
C3_FUNC=$(( (FUNC_APPS + 24) / 25 ))
C3_CAAS=$(( (CAAS_COUNT + 9) / 10 ))
C3_AKS=$(( AKS_NODES )) 
C3_ACR=$(( ACR_COUNT ))

TOTAL_C3=$(( C3_VM + C3_FUNC + C3_CAAS + C3_AKS + C3_ACR ))
TOTAL_CREDITS=$(( TOTAL_C1 + TOTAL_C3 ))

# 4. Output Results
echo ""
echo "=================================================="
echo " FINAL REPORT (Aggregated from $SUB_COUNT Subscriptions)"
echo "=================================================="
printf "%-35s %-10s\n" "RESOURCE TYPE" "COUNT"
echo "--------------------------------------------------"
printf "%-35s %-10s\n" "VMs" "$VM_COUNT"
printf "%-35s %-10s\n" "AKS/Container Nodes" "$AKS_NODES"
printf "%-35s %-10s\n" "CaaS (ACI/ACA)" "$CAAS_COUNT"
printf "%-35s %-10s\n" "Function Apps" "$FUNC_APPS"
printf "%-35s %-10s\n" "Total PaaS Databases" "$TOTAL_PAAS_DBS"
printf "%-35s %-10s\n" "  - SQL Servers" "$SQL_SERVERS"
printf "%-35s %-10s\n" "  - SQL Managed Instances" "$SQL_MI"
printf "%-35s %-10s\n" "  - Cosmos DB" "$COSMOS_DBS"
printf "%-35s %-10s\n" "  - Open Source DBs" "$OS_DBS"
printf "%-35s %-10s\n" "Storage Accounts" "$STORAGE_ACCS"
printf "%-35s %-10s\n" "Container Registries" "$ACR_COUNT"
