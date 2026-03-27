#!/bin/bash
set -euo pipefail

# ============================================================
# 04-verify.sh
# Run after: az login --tenant $TENANT_A_ID
# Manually triggers the pipeline and verifies data arrived in Blob-B
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"

echo "=========================================="
echo " Verifying cross-tenant blob sync"
echo "=========================================="

az account set --subscription "$SUB_A_ID"
az extension add --name datafactory 2>/dev/null || true

# ---- 1. List source blobs ----
echo "[1/4] Listing source blobs in Blob-A..."
az storage blob list \
    --account-name "$STORAGE_A" \
    --container-name "$CONTAINER_A" \
    --auth-mode login \
    --query "[].{name:name, size:properties.contentLength}" \
    --output table

# ---- 2. Trigger pipeline run ----
echo ""
echo "[2/4] Triggering pipeline-blob-sync manually..."
RUN_ID=$(az datafactory pipeline create-run \
    --factory-name "$ADF_NAME" \
    --resource-group "$RG_A" \
    --pipeline-name "pipeline-blob-sync" \
    --query runId -o tsv)
echo "       Run ID: $RUN_ID"

# ---- 3. Wait for completion ----
echo ""
echo "[3/4] Waiting for pipeline run to complete..."
for i in $(seq 1 30); do
    STATUS=$(az datafactory pipeline-run show \
        --factory-name "$ADF_NAME" \
        --resource-group "$RG_A" \
        --run-id "$RUN_ID" \
        --query status -o tsv 2>/dev/null || echo "Queued")

    echo "       Attempt $i/30 - Status: $STATUS"

    if [[ "$STATUS" == "Succeeded" ]]; then
        echo "       Pipeline run succeeded!"
        break
    elif [[ "$STATUS" == "Failed" ]]; then
        echo "ERROR: Pipeline run FAILED."
        az datafactory pipeline-run show \
            --factory-name "$ADF_NAME" \
            --resource-group "$RG_A" \
            --run-id "$RUN_ID" \
            --query message -o tsv
        exit 1
    fi
    sleep 10
done

if [[ "$STATUS" != "Succeeded" ]]; then
    echo "WARNING: Pipeline still running after 5 minutes. Check ADF portal."
fi

# ---- 4. Verify destination blobs ----
echo ""
echo "[4/4] Verifying blobs arrived in Blob-B..."
echo "       (Logging in to Tenant B with SP to check...)"

# Use SP to list blobs in Tenant B (no need to re-login)
az storage blob list \
    --account-name "$STORAGE_B" \
    --container-name "$CONTAINER_B" \
    --auth-mode login \
    --query "[].{name:name, size:properties.contentLength, lastModified:properties.lastModified}" \
    --output table \
    --account-key "$(az storage account keys list \
        --account-name "$STORAGE_B" \
        --query "[0].value" -o tsv \
        --subscription "$SUB_B_ID" 2>/dev/null || echo "")" 2>/dev/null || {
    echo ""
    echo "  Cannot list Blob-B from Tenant A context."
    echo "  To verify manually, run:"
    echo "    az login --tenant $TENANT_B_ID"
    echo "    az storage blob list --account-name $STORAGE_B --container-name $CONTAINER_B --auth-mode login --output table"
}

echo ""
echo "=========================================="
echo " Verification COMPLETE"
echo "=========================================="
echo ""
echo " To verify from Tenant B side:"
echo "   az login --tenant $TENANT_B_ID"
echo "   az account set --subscription $SUB_B_ID"
echo "   az storage blob list --account-name $STORAGE_B --container-name $CONTAINER_B --auth-mode login --output table"
