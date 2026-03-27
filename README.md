# Cross-Tenant Blob Storage Sync with Azure Data Factory

A demo that syncs data from Blob Storage in **Tenant A** to Blob Storage in **Tenant B** using Azure Data Factory, with a daily schedule trigger.

## Architecture

```
┌─────────────────────────────────────────┐     ┌──────────────────────────────────┐
│            Tenant A                     │     │           Tenant B               │
│                                         │     │                                  │
│  ┌─────────────┐    ┌──────────────┐    │     │    ┌──────────────┐              │
│  │  Blob-A     │───>│  Azure Data  │────│─────│───>│  Blob-B      │              │
│  │  (source)   │ MI │  Factory     │ SP │     │    │  (dest)      │              │
│  └─────────────┘    └──────────────┘    │     │    └──────────────┘              │
│                                         │     │                                  │
│                                         │     │    ┌──────────────┐              │
│                                         │     │    │  Service     │              │
│                                         │     │    │  Principal   │              │
│                                         │     │    └──────────────┘              │
└─────────────────────────────────────────┘     └──────────────────────────────────┘
```

## Authentication Strategy

| Connection | Auth Method | Reason |
|------------|-------------|--------|
| ADF → Blob-A (same tenant) | **Managed Identity** | Most secure, no credentials to manage |
| ADF → Blob-B (cross-tenant) | **Service Principal** | MI cannot authenticate across tenants; SP is the only viable option |

The Service Principal is created in **Tenant B**. ADF in Tenant A uses the SP's **App ID + Secret + Tenant B's Tenant ID** to request a token directly from Tenant B's Azure AD via the OAuth2 Client Credentials flow.

## Prerequisites

- Azure CLI (`az`) installed
- Admin access to two Azure tenants
- An active Azure subscription in each tenant
- ADF CLI extension: `az extension add --name datafactory`

## File Overview

| File | Description |
|------|-------------|
| `env.sh.example` | Environment config template (copy to `env.sh` and fill in values) |
| `01-setup-tenant-a.sh` | Creates Tenant A resources (Storage, ADF, uploads test data) |
| `02-setup-tenant-b.sh` | Creates Tenant B resources (Storage, Service Principal, role assignment) |
| `03-setup-adf-pipeline.sh` | Creates ADF pipeline (Linked Services, Datasets, Pipeline, Trigger) |
| `04-verify.sh` | Manually triggers the pipeline and verifies data sync |
| `05-cleanup.sh` | Cleans up all resources in both tenants |
| `data/sample-sales.csv` | Sample test data |

## Usage

### Step 1: Configure Environment Variables

```bash
cp env.sh.example env.sh
```

Edit `env.sh` and fill in:
- `TENANT_A_ID` / `SUB_A_ID` — Tenant A directory (tenant) ID and subscription ID
- `TENANT_B_ID` / `SUB_B_ID` — Tenant B directory (tenant) ID and subscription ID
- `STORAGE_A` / `STORAGE_B` — Globally unique storage account names (3-24 chars, lowercase + numbers only)

### Step 2: Set Up Tenant A Resources

```bash
az login --tenant <TENANT_A_ID>
chmod +x *.sh
./01-setup-tenant-a.sh
```

This creates a Resource Group, Storage Account, uploads test data, and creates an Azure Data Factory with Managed Identity.

### Step 3: Set Up Tenant B Resources + Service Principal

```bash
az login --tenant <TENANT_B_ID>
./02-setup-tenant-b.sh
```

This creates a Resource Group, Storage Account, and a Service Principal with `Storage Blob Data Contributor` role on Storage B. SP credentials are automatically saved to `env.sh`.

### Step 4: Create ADF Pipeline + Daily Trigger

```bash
az login --tenant <TENANT_A_ID>
./03-setup-adf-pipeline.sh
```

This creates Linked Services (MI for source, SP for destination), Datasets, a Copy Pipeline, and a daily schedule trigger.

### Step 5: Verify

```bash
./04-verify.sh
```

To verify from the Tenant B side:
```bash
az login --tenant <TENANT_B_ID>
az storage blob list --account-name <STORAGE_B> --container-name dest-data --auth-mode login --output table
```

### Step 6: Cleanup

```bash
./05-cleanup.sh
```

## Schedule

- Trigger: `trigger-daily-sync`
- Frequency: Once per day
- Time: 02:00 CST (UTC+8)
- Can be modified in the ADF portal

## Security Notes

- SP Secret is stored locally in `env.sh` — clean up promptly after the demo
- `env.sh` is excluded from git via `.gitignore`
- Storage Accounts have public blob access disabled
- Minimum TLS version is set to 1.2

## Production Recommendations

### Credential Management
- Store SP Secret in **Azure Key Vault** and reference it via ADF Key Vault Linked Service
- Set a short SP Secret expiry (e.g., 90 days) with an automatic rotation policy
- Use **Federated Identity Credentials** (Workload Identity Federation) to eliminate SP secrets entirely for cross-tenant auth

### Network Security
- Enable **Private Endpoints** on Storage Accounts and disable public network access
- Configure ADF **Managed Virtual Network** + **Private Endpoints** to keep data transfer off the public internet
- Set up Storage Account **firewall rules** to allow access only from ADF's managed VNet

### Monitoring & Alerting
- Enable **ADF diagnostic logs** and send them to a Log Analytics Workspace
- Set up **Azure Monitor alerts** for pipeline failures (email/Teams notifications)
- Monitor SP Secret expiration dates with proactive alerts

### Data Sync Strategy
- Use **incremental copy** (based on file modification time or watermark) instead of full copy to reduce cost and latency
- Enable ADF **data validation** (checksum/row count) to ensure source-destination consistency
- Enable **Soft Delete** and **versioning** on Storage Accounts for critical data

### High Availability
- ADF is a managed service with built-in HA; configure **retry policies** (retry count + interval) at the pipeline activity level
- Choose **GRS/GZRS** redundancy for Storage Accounts
- Use **ADF global parameters** and **CI/CD (ARM template export)** for multi-environment deployment management
