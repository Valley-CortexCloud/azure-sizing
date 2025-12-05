#!/bin/bash

# --- Cortex XSIAM Sizing Script (Azure Native) ---
# No dependencies. Runs instantly via Azure Resource Graph.

echo "=================================================="
echo "   CORTEX XSIAM - CLOUD SIZING CALCULATOR"
echo "=================================================="

# Get Sub Info
SUB_ID=$(az account show --query id -o tsv)
SUB_NAME=$(az account show --query name -o tsv)
echo "Targeting Subscription: $SUB_NAME ($SUB_ID)"
echo "Analyzing resources..."

# 1. Run Fast Queries (using Azure Resource Graph)
# We use || echo 0 to handle empty results gracefully
VM_COUNT=$(az graph query -q "Resources | where type =~ 'Microsoft.Compute/virtualMachines' and properties.extended.instanceView.powerState.code == 'PowerState/running' | count" --query "data[0].count_0" -o tsv 2>/dev/null || echo 0)

AKS_NODES=$(az graph query -q "Resources | where type =~ 'Microsoft.ContainerService/managedClusters' | project id | join kind=leftouter (Resources | where type =~ 'Microsoft.Compute/virtualMachineScaleSets' | where sku.capacity > 0) on \$left.id == \$right.properties.virtualMachineProfile.osProfile.customData | summarize count()" --query "data[0].count_" -o tsv 2>/dev/null || echo 0)

FUNC_APPS=$(az graph query -q "Resources | where type =~ 'Microsoft.Web/sites' and kind contains 'function' | count" --query "data[0].count_0" -o tsv 2>/dev/null || echo 0)

SQL_DBS=$(az graph query -q "Resources | where type =~ 'Microsoft.Sql/servers/databases' and name != 'master' | count" --query "data[0].count_0" -o tsv 2>/dev/null || echo 0)

COSMOS_DBS=$(az graph query -q "Resources | where type =~ 'Microsoft.DocumentDB/databaseAccounts' | count" --query "data[0].count_0" -o tsv 2>/dev/null || echo 0)

STORAGE_ACCS=$(az graph query -q "Resources | where type =~ 'Microsoft.Storage/storageAccounts' | count" --query "data[0].count_0" -o tsv 2>/dev/null || echo 0)

# 2. Calculate Credits (Rounding Up Logic)
# Logic: (Count + UnitSize - 1) / UnitSize performs ceiling division in Bash integer math

# C1: Data/Storage
# Storage: /10, DBs: /2
C1_STORAGE=$(( (STORAGE_ACCS + 9) / 10 ))
C1_DB=$(( (SQL_DBS + COSMOS_DBS + 1) / 2 ))
TOTAL_C1=$(( C1_STORAGE + C1_DB ))

# C3: Compute
# VMs: /1, Serverless: /25, Containers: /10
C3_VM=$(( VM_COUNT ))
C3_FUNC=$(( (FUNC_APPS + 24) / 25 ))
C3_CONT=$(( (AKS_NODES + 9) / 10 ))
TOTAL_C3=$(( C3_VM + C3_FUNC + C3_CONT ))

TOTAL_CREDITS=$(( TOTAL_C1 + TOTAL_C3 ))

# 3. Output Results
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
