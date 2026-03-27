#!/bin/bash
set -euo pipefail

# ============================================================
# 02-setup-tenant-b.sh
# Run after: az login --tenant $TENANT_B_ID
# Creates: Resource Group, Storage Account, Service Principal
# Grants SP "Storage Blob Data Contributor" on Storage B
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"

echo "=========================================="
echo " Setting up Tenant B resources"
echo "=========================================="

# Validate required variables
if [[ -z "$TENANT_B_ID" || -z "$SUB_B_ID" ]]; then
    echo "ERROR: Please fill in TENANT_B_ID and SUB_B_ID in env.sh"
    exit 1
fi

# Set subscription
az account set --subscription "$SUB_B_ID"
echo "[1/5] Subscription set to: $SUB_B_ID"

# Create Resource Group
az group create --name "$RG_B" --location "$LOCATION_B" --output none
echo "[2/5] Resource group '$RG_B' created"

# Create Storage Account B
az storage account create \
    --name "$STORAGE_B" \
    --resource-group "$RG_B" \
    --location "$LOCATION_B" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    --output none
echo "[3/5] Storage account '$STORAGE_B' created"

# Create container
az storage container create \
    --name "$CONTAINER_B" \
    --account-name "$STORAGE_B" \
    --auth-mode login \
    --output none
echo "[4/5] Container '$CONTAINER_B' created"

# Create Service Principal in Tenant B for cross-tenant access
echo "[5/5] Creating Service Principal '$SP_NAME' in Tenant B..."

# Check if SP already exists
EXISTING_APP_ID=$(az ad app list --display-name "$SP_NAME" --query "[0].appId" -o tsv 2>/dev/null || true)
if [[ -n "$EXISTING_APP_ID" && "$EXISTING_APP_ID" != "None" ]]; then
    echo "       SP '$SP_NAME' already exists (AppId: $EXISTING_APP_ID). Resetting credentials..."
    SP_CRED=$(az ad app credential reset --id "$EXISTING_APP_ID" --query "{appId:appId, password:password}" -o json)
    SP_APP_ID="$EXISTING_APP_ID"
    SP_SECRET=$(echo "$SP_CRED" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")
else
    # Create new app registration + SP
    SP_APP_ID=$(az ad app create --display-name "$SP_NAME" --query appId -o tsv)
    az ad sp create --id "$SP_APP_ID" --output none
    SP_CRED=$(az ad app credential reset --id "$SP_APP_ID" --query "{appId:appId, password:password}" -o json)
    SP_SECRET=$(echo "$SP_CRED" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")
fi

SP_OBJECT_ID=$(az ad sp show --id "$SP_APP_ID" --query id -o tsv)

echo "       SP App ID    : $SP_APP_ID"
echo "       SP Object ID : $SP_OBJECT_ID"
echo "       SP Secret    : ****${SP_SECRET: -4}"

# Assign Storage Blob Data Contributor to SP on Storage B
az role assignment create \
    --role "Storage Blob Data Contributor" \
    --assignee-object-id "$SP_OBJECT_ID" \
    --assignee-principal-type ServicePrincipal \
    --scope "/subscriptions/$SUB_B_ID/resourceGroups/$RG_B/providers/Microsoft.Storage/storageAccounts/$STORAGE_B" \
    --output none
echo "       SP granted 'Storage Blob Data Contributor' on Storage B"

# Save SP credentials back to env.sh
sed -i.bak "s|^export SP_APP_ID=.*|export SP_APP_ID=\"$SP_APP_ID\"|" "$SCRIPT_DIR/env.sh"
sed -i.bak "s|^export SP_SECRET=.*|export SP_SECRET=\"$SP_SECRET\"|" "$SCRIPT_DIR/env.sh"
sed -i.bak "s|^export SP_OBJECT_ID=.*|export SP_OBJECT_ID=\"$SP_OBJECT_ID\"|" "$SCRIPT_DIR/env.sh"
rm -f "$SCRIPT_DIR/env.sh.bak"

echo ""
echo "=========================================="
echo " Tenant B setup COMPLETE"
echo "=========================================="
echo " Storage B  : $STORAGE_B"
echo " Container  : $CONTAINER_B"
echo " SP App ID  : $SP_APP_ID"
echo " SP Secret  : saved to env.sh"
echo ""
echo " Next step: az login --tenant $TENANT_A_ID"
echo "            then run: ./03-setup-adf-pipeline.sh"
