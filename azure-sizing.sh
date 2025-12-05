#!/bin/bash

# --- Cortex Cloud Sizing (Azure Native - Multi-Sub) ---
# Hosted by: Valley-CortexCloud
# Purpose: Robust sizing for Azure Cloud (Scans ALL Subscriptions)

# 0. Self-Healing: Install required Azure Extensions silently
az config set extension.use_dynamic_install=yes_without_prompt 2>/dev/null
if ! az extension show --name resource-graph &>/dev/null; then
    echo "Initializing Azure Resource Graph..."
    az extension add --name resource-graph &>/dev/null
fi

echo "=================================================="
echo "   CORTEX CLOUD - CLOUD SIZING CALCULATOR"
echo "=================================================="

# 1. Get ALL Active Subscriptions
# We fetch all IDs and format them as a space-separated list for the query
echo "Fetching subscription list..."
ALL_SUBS=$(az account list --query "[?state=='Enabled'].id" -o tsv | tr '\n' ' ')
SUB_COUNT=$(echo "$ALL_SUBS" | wc -w)

if [[ -z "$ALL_SUBS" ]]; then
    echo "Error: No active subscriptions found."
    exit 1
fi

echo "Targeting Scope: $SUB_COUNT Subscription(s)"
echo "Analyzing resources across entire environment..."

# HELPER FUNCTION: Runs query against ALL subs and ensures 0 is returned if empty
run_query() {
    local query="$1"
    # We pass $ALL_SUBS to the --subscriptions flag to force global scope
    local result=$(az graph query -q "$query | summarize Val=count()" --subscriptions $ALL_SUBS --query "data[0].Val" -o tsv 2>/dev/null)
    
    if [[ -z "$result" ]]; then
        echo "0"
    else
        echo "$result"
    fi
}

# 2. Run Queries (Now scoped to all subscriptions)

# VMs (Running)
VM_COUNT=$(run_query "Resources | where type =~ 'Microsoft.Compute/virtualMachines' and properties.extended.instanceView.powerState.code == 'PowerState/running'")

# AKS Nodes (Complex join)
AKS_NODES=$(run_query "Resources | where type =~ 'Microsoft.ContainerService/managedClusters' | project id | join kind=leftouter (Resources | where type =~ 'Microsoft.Compute/virtualMachineScaleSets' | where sku.capacity > 0) on \$left.id == \$right.properties.virtualMachineProfile.osProfile.customData")

# Function Apps
FUNC_APPS=$(run_query "Resources | where type =~ 'Microsoft.Web/sites' and kind contains 'function'")

# SQL Databases
SQL_DBS=$(run_query "Resources | where type =~ 'Microsoft.Sql/servers/databases' and name != 'master'")

# Cosmos DB
COSMOS_DBS=$(run_query "Resources | where type =~ 'Microsoft.DocumentDB/databaseAccounts'")

# Storage Accounts
STORAGE_ACCS=$(run_query "Resources | where type =~ 'Microsoft.Storage/storageAccounts'")

# 3. Calculate Credits
# Logic: (Count + UnitSize - 1) / UnitSize performs ceiling division

# C1: Data/Storage (Storage /10, DBs /2)
C1_STORAGE=$(( (STORAGE_ACCS + 9) / 10 ))
C1_DB=$(( (SQL_DBS + COSMOS_DBS + 1) / 2 ))
TOTAL_C1=$(( C1_STORAGE + C1_DB ))

# C3: Compute (VMs /1, Serverless /25, Containers /10)
C3_VM=$(( VM_COUNT ))
C3_FUNC=$(( (FUNC_APPS + 24) / 25 ))
C3_CONT=$(( (AKS_NODES + 9) / 10 ))
TOTAL_C3=$(( C3_VM + C3_FUNC + C3_CONT ))

TOTAL_CREDITS=$(( TOTAL_C1 + TOTAL_C3 ))

# 4. Output Results
echo "--------------------------------------------------"
printf "%-30s %-10s\n" "RESOURCE TYPE" "COUNT"
echo "--------------------------------------------------"
printf "%-30s %-10s\n" "VMs (Running)" "$VM_COUNT"
printf "%-30s %-10s\n" "AKS/Container Nodes" "$AKS_NODES"
printf "%-30s %-10s\n" "Function Apps" "$FUNC_APPS"
printf "%-30s %-10s\n" "SQL Databases" "$SQL_DBS"
printf "%-30s %-10s\n" "Cosmos DB Accounts" "$COSMOS_DBS"
printf "%-30s %-10s\n" "Storage Accounts" "$STORAGE_ACCS"
echo "=================================================="
echo " ESTIMATED LICENSING (CREDITS)"
echo "=================================================="
echo "  C1 (Data & Storage):  $TOTAL_C1 credits"
echo "  C3 (Cloud Compute):   $TOTAL_C3 credits"
echo "--------------------------------------------------"
echo "  TOTAL REQUIRED:       $TOTAL_CREDITS credits"
echo "=================================================="
