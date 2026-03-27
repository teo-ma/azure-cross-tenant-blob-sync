#!/bin/bash
set -euo pipefail

# ============================================================
# 05-cleanup.sh
# Cleans up ALL resources in both tenants
# Run twice: once logged into each tenant
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"

echo "=========================================="
echo " Cleanup - Cross-tenant blob sync demo"
echo "=========================================="
echo ""
echo "This script will DELETE all demo resources."
echo ""

read -rp "Which tenant are you logged into? (a/b/both): " CHOICE

cleanup_tenant_a() {
    echo ""
    echo "--- Cleaning up Tenant A ---"
    az account set --subscription "$SUB_A_ID"

    echo "  Deleting resource group '$RG_A'..."
    az group delete --name "$RG_A" --yes --no-wait
    echo "  Resource group '$RG_A' deletion initiated (async)"
}

cleanup_tenant_b() {
    echo ""
    echo "--- Cleaning up Tenant B ---"
    az account set --subscription "$SUB_B_ID"

    # Delete SP first
    if [[ -n "$SP_APP_ID" ]]; then
        echo "  Deleting Service Principal (App ID: $SP_APP_ID)..."
        az ad app delete --id "$SP_APP_ID" 2>/dev/null || true
        echo "  SP deleted"
    fi

    echo "  Deleting resource group '$RG_B'..."
    az group delete --name "$RG_B" --yes --no-wait
    echo "  Resource group '$RG_B' deletion initiated (async)"
}

case "$CHOICE" in
    a|A)
        cleanup_tenant_a
        echo ""
        echo "Now run: az login --tenant $TENANT_B_ID"
        echo "Then:    ./05-cleanup.sh  (choose 'b')"
        ;;
    b|B)
        cleanup_tenant_b
        ;;
    both|BOTH)
        echo ""
        echo "Cleaning Tenant A first..."
        echo "Make sure you have access to both tenants in the current session."
        cleanup_tenant_a
        echo ""
        echo "Switching to Tenant B..."
        echo "NOTE: You may need to run 'az login --tenant $TENANT_B_ID' manually"
        echo "      if multi-tenant session is not active."
        cleanup_tenant_b
        ;;
    *)
        echo "Invalid choice. Use 'a', 'b', or 'both'."
        exit 1
        ;;
esac

# Reset SP credentials in env.sh
sed -i.bak 's|^export SP_APP_ID=.*|export SP_APP_ID=""|' "$SCRIPT_DIR/env.sh"
sed -i.bak 's|^export SP_SECRET=.*|export SP_SECRET=""|' "$SCRIPT_DIR/env.sh"
sed -i.bak 's|^export SP_OBJECT_ID=.*|export SP_OBJECT_ID=""|' "$SCRIPT_DIR/env.sh"
rm -f "$SCRIPT_DIR/env.sh.bak"

echo ""
echo "=========================================="
echo " Cleanup COMPLETE"
echo "=========================================="
echo " Resource groups are being deleted asynchronously."
echo " It may take a few minutes for full deletion."
