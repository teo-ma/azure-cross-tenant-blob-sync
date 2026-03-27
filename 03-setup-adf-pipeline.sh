#!/bin/bash
set -euo pipefail

# ============================================================
# 03-setup-adf-pipeline.sh
# Run after: az login --tenant $TENANT_A_ID
# Creates: ADF Linked Services, Datasets, Pipeline, Daily Trigger
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"

echo "=========================================="
echo " Setting up ADF Pipeline"
echo "=========================================="

# Validate required variables
if [[ -z "$SP_APP_ID" || -z "$SP_SECRET" ]]; then
    echo "ERROR: SP_APP_ID and SP_SECRET not found in env.sh."
    echo "       Run 02-setup-tenant-b.sh first."
    exit 1
fi

az account set --subscription "$SUB_A_ID"

# Ensure datafactory extension is installed
az extension add --name datafactory 2>/dev/null || true

STORAGE_A_URL="https://${STORAGE_A}.blob.core.windows.net"
STORAGE_B_URL="https://${STORAGE_B}.blob.core.windows.net"

# ---- 1. Linked Service: Source Blob-A (ADF Managed Identity) ----
echo "[1/6] Creating Linked Service for Blob-A (Managed Identity)..."

cat > /tmp/ls-blob-a.json << EOF
{
    "type": "AzureBlobStorage",
    "typeProperties": {
        "serviceEndpoint": "$STORAGE_A_URL",
        "accountKind": "StorageV2"
    }
}
EOF

az datafactory linked-service create \
    --factory-name "$ADF_NAME" \
    --resource-group "$RG_A" \
    --linked-service-name "ls-blob-source-a" \
    --properties @/tmp/ls-blob-a.json \
    --output none
echo "       ls-blob-source-a created (Managed Identity)"

# ---- 2. Linked Service: Dest Blob-B (Service Principal) ----
echo "[2/6] Creating Linked Service for Blob-B (Service Principal)..."

cat > /tmp/ls-blob-b.json << EOF
{
    "type": "AzureBlobStorage",
    "typeProperties": {
        "serviceEndpoint": "$STORAGE_B_URL",
        "accountKind": "StorageV2",
        "tenant": "$TENANT_B_ID",
        "servicePrincipalId": "$SP_APP_ID",
        "servicePrincipalKey": {
            "type": "SecureString",
            "value": "$SP_SECRET"
        }
    }
}
EOF

az datafactory linked-service create \
    --factory-name "$ADF_NAME" \
    --resource-group "$RG_A" \
    --linked-service-name "ls-blob-dest-b" \
    --properties @/tmp/ls-blob-b.json \
    --output none
echo "       ls-blob-dest-b created (Service Principal)"

# ---- 3. Dataset: Source ----
echo "[3/6] Creating source dataset..."

cat > /tmp/ds-source.json << EOF
{
    "type": "DelimitedText",
    "linkedServiceName": {
        "referenceName": "ls-blob-source-a",
        "type": "LinkedServiceReference"
    },
    "typeProperties": {
        "location": {
            "type": "AzureBlobStorageLocation",
            "container": "$CONTAINER_A",
            "folderPath": "sales"
        },
        "columnDelimiter": ",",
        "firstRowAsHeader": true,
        "quoteChar": "\""
    },
    "schema": []
}
EOF

az datafactory dataset create \
    --factory-name "$ADF_NAME" \
    --resource-group "$RG_A" \
    --dataset-name "ds-source-csv" \
    --properties @/tmp/ds-source.json \
    --output none
echo "       ds-source-csv created"

# ---- 4. Dataset: Sink ----
echo "[4/6] Creating sink dataset..."

cat > /tmp/ds-sink.json << EOF
{
    "type": "DelimitedText",
    "linkedServiceName": {
        "referenceName": "ls-blob-dest-b",
        "type": "LinkedServiceReference"
    },
    "typeProperties": {
        "location": {
            "type": "AzureBlobStorageLocation",
            "container": "$CONTAINER_B",
            "folderPath": "synced-data"
        },
        "columnDelimiter": ",",
        "firstRowAsHeader": true,
        "quoteChar": "\""
    },
    "schema": []
}
EOF

az datafactory dataset create \
    --factory-name "$ADF_NAME" \
    --resource-group "$RG_A" \
    --dataset-name "ds-sink-csv" \
    --properties @/tmp/ds-sink.json \
    --output none
echo "       ds-sink-csv created"

# ---- 5. Pipeline: Copy ----
echo "[5/6] Creating copy pipeline..."

cat > /tmp/pipeline.json << EOF
{
    "activities": [
        {
            "name": "CopyBlobAToB",
            "type": "Copy",
            "inputs": [
                {
                    "referenceName": "ds-source-csv",
                    "type": "DatasetReference"
                }
            ],
            "outputs": [
                {
                    "referenceName": "ds-sink-csv",
                    "type": "DatasetReference"
                }
            ],
            "typeProperties": {
                "source": {
                    "type": "DelimitedTextSource",
                    "storeSettings": {
                        "type": "AzureBlobStorageReadSettings",
                        "recursive": true,
                        "wildcardFileName": "*.csv"
                    },
                    "formatSettings": {
                        "type": "DelimitedTextReadSettings"
                    }
                },
                "sink": {
                    "type": "DelimitedTextSink",
                    "storeSettings": {
                        "type": "AzureBlobStorageWriteSettings"
                    },
                    "formatSettings": {
                        "type": "DelimitedTextWriteSettings",
                        "quoteAllText": true
                    }
                }
            }
        }
    ]
}
EOF

az datafactory pipeline create \
    --factory-name "$ADF_NAME" \
    --resource-group "$RG_A" \
    --pipeline-name "pipeline-blob-sync" \
    --pipeline @/tmp/pipeline.json \
    --output none
echo "       pipeline-blob-sync created"

# ---- 6. Trigger: Daily ----
echo "[6/6] Creating daily schedule trigger..."

cat > /tmp/trigger.json << EOF
{
    "type": "ScheduleTrigger",
    "typeProperties": {
        "recurrence": {
            "frequency": "Day",
            "interval": 1,
            "startTime": "2026-03-27T02:00:00Z",
            "timeZone": "China Standard Time"
        }
    },
    "pipelines": [
        {
            "pipelineReference": {
                "referenceName": "pipeline-blob-sync",
                "type": "PipelineReference"
            }
        }
    ]
}
EOF

az datafactory trigger create \
    --factory-name "$ADF_NAME" \
    --resource-group "$RG_A" \
    --trigger-name "trigger-daily-sync" \
    --properties @/tmp/trigger.json \
    --output none
echo "       trigger-daily-sync created"

# Start the trigger
az datafactory trigger start \
    --factory-name "$ADF_NAME" \
    --resource-group "$RG_A" \
    --trigger-name "trigger-daily-sync" \
    --output none
echo "       trigger-daily-sync started"

# Clean up temp files
rm -f /tmp/ls-blob-a.json /tmp/ls-blob-b.json /tmp/ds-source.json /tmp/ds-sink.json /tmp/pipeline.json /tmp/trigger.json

echo ""
echo "=========================================="
echo " ADF Pipeline setup COMPLETE"
echo "=========================================="
echo " Pipeline    : pipeline-blob-sync"
echo " Trigger     : trigger-daily-sync (daily at 02:00 CST)"
echo ""
echo " To manually trigger a run:"
echo "   ./04-verify.sh"
