#!/bin/bash
set -euo pipefail

# ============================================================
# 01-setup-tenant-a.sh
# Run after: az login --tenant $TENANT_A_ID
# Creates: Resource Group, Storage Account, ADF, uploads test data
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"

echo "=========================================="
echo " Setting up Tenant A resources"
echo "=========================================="

# Validate required variables
if [[ -z "$TENANT_A_ID" || -z "$SUB_A_ID" ]]; then
    echo "ERROR: Please fill in TENANT_A_ID and SUB_A_ID in env.sh"
    exit 1
fi

# Set subscription
az account set --subscription "$SUB_A_ID"
echo "[1/6] Subscription set to: $SUB_A_ID"

# Create Resource Group
az group create --name "$RG_A" --location "$LOCATION_A" --output none
echo "[2/6] Resource group '$RG_A' created"

# Create Storage Account A
az storage account create \
    --name "$STORAGE_A" \
    --resource-group "$RG_A" \
    --location "$LOCATION_A" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    --output none
echo "[3/6] Storage account '$STORAGE_A' created"

# Create container
az storage container create \
    --name "$CONTAINER_A" \
    --account-name "$STORAGE_A" \
    --auth-mode login \
    --output none
echo "[4/6] Container '$CONTAINER_A' created"

# Assign current user Storage Blob Data Contributor on Storage A (for uploading data)
CURRENT_USER_OID=$(az ad signed-in-user show --query id -o tsv)
az role assignment create \
    --role "Storage Blob Data Contributor" \
    --assignee-object-id "$CURRENT_USER_OID" \
    --assignee-principal-type User \
    --scope "/subscriptions/$SUB_A_ID/resourceGroups/$RG_A/providers/Microsoft.Storage/storageAccounts/$STORAGE_A" \
    --output none 2>/dev/null || true
echo "[5/6] Role assigned to current user on Storage A"

# Upload test data
echo "    Waiting for role assignment to propagate..."
sleep 15
az storage blob upload \
    --account-name "$STORAGE_A" \
    --container-name "$CONTAINER_A" \
    --name "sales/sample-sales.csv" \
    --file "$SCRIPT_DIR/data/sample-sales.csv" \
    --auth-mode login \
    --overwrite \
    --output none
echo "[5/6] Test data uploaded to Blob-A"

# Create Azure Data Factory
az datafactory create \
    --name "$ADF_NAME" \
    --resource-group "$RG_A" \
    --location "$LOCATION_A" \
    --output none
echo "[6/6] Azure Data Factory '$ADF_NAME' created"

# Assign ADF Managed Identity -> Storage Blob Data Reader on Storage A
ADF_MI_OID=$(az datafactory show \
    --name "$ADF_NAME" \
    --resource-group "$RG_A" \
    --query identity.principalId -o tsv)
az role assignment create \
    --role "Storage Blob Data Reader" \
    --assignee-object-id "$ADF_MI_OID" \
    --assignee-principal-type ServicePrincipal \
    --scope "/subscriptions/$SUB_A_ID/resourceGroups/$RG_A/providers/Microsoft.Storage/storageAccounts/$STORAGE_A" \
    --output none
echo "       ADF MI ($ADF_MI_OID) granted 'Storage Blob Data Reader' on Storage A"

echo ""
echo "=========================================="
echo " Tenant A setup COMPLETE"
echo "=========================================="
echo " Storage A : $STORAGE_A"
echo " Container : $CONTAINER_A"
echo " ADF       : $ADF_NAME"
echo " ADF MI OID: $ADF_MI_OID"
echo ""
echo " Next step: az login --tenant $TENANT_B_ID"
echo "            then run: ./02-setup-tenant-b.sh"
