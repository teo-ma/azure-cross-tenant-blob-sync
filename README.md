# Cross-Tenant Blob Storage Sync with Azure Data Factory

使用 Azure Data Factory 实现跨租户 Blob Storage 数据同步的 Demo。

## 架构图

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

## 认证策略

| 连接 | 认证方式 | 原因 |
|------|----------|------|
| ADF → Blob-A (同租户) | **Managed Identity** | 最安全，无需管理凭据 |
| ADF → Blob-B (跨租户) | **Service Principal** | MI 无法跨租户认证，SP 是唯一可行方案 |

## 前置条件

- Azure CLI (`az`) 已安装
- 拥有两个 Azure 租户的管理员权限
- 两个租户各有一个活跃的 Azure 订阅
- 安装 ADF CLI 扩展: `az extension add --name datafactory`

## 文件说明

| 文件 | 说明 |
|------|------|
| `env.sh` | 环境配置（租户 ID、订阅 ID、资源名称） |
| `01-setup-tenant-a.sh` | 创建 Tenant A 资源（Storage、ADF、上传测试数据） |
| `02-setup-tenant-b.sh` | 创建 Tenant B 资源（Storage、SP、角色分配） |
| `03-setup-adf-pipeline.sh` | 创建 ADF 管道（Linked Service、Dataset、Pipeline、Trigger） |
| `04-verify.sh` | 手动触发管道并验证数据同步 |
| `05-cleanup.sh` | 清理所有资源 |
| `data/sample-sales.csv` | 测试数据 |

## 使用步骤

### Step 1: 配置环境变量

编辑 `env.sh`，填写：
- `TENANT_A_ID` / `SUB_A_ID` — Tenant A 的租户 ID 和订阅 ID
- `TENANT_B_ID` / `SUB_B_ID` — Tenant B 的租户 ID 和订阅 ID
- `STORAGE_A` / `STORAGE_B` — 全局唯一的存储账户名（3-24字符，仅小写字母和数字）

```bash
vim env.sh
```

### Step 2: 创建 Tenant A 资源

```bash
az login --tenant <TENANT_A_ID>
chmod +x *.sh
./01-setup-tenant-a.sh
```

### Step 3: 创建 Tenant B 资源 + Service Principal

```bash
az login --tenant <TENANT_B_ID>
./02-setup-tenant-b.sh
```

> SP 的 AppId 和 Secret 会自动写入 `env.sh`。

### Step 4: 创建 ADF 管道 + 每日触发器

```bash
az login --tenant <TENANT_A_ID>
./03-setup-adf-pipeline.sh
```

### Step 5: 验证

```bash
./04-verify.sh
```

验证完成后，可以切换到 Tenant B 查看到达的数据：
```bash
az login --tenant <TENANT_B_ID>
az storage blob list --account-name <STORAGE_B> --container-name dest-data --auth-mode login --output table
```

### Step 6: 清理

```bash
./05-cleanup.sh
```

## 管道调度

- 触发器: `trigger-daily-sync`
- 频率: 每天一次
- 时间: 北京时间 02:00 (UTC+8)
- 可在 ADF 门户中修改调度时间

## 安全注意事项

- SP Secret 存储在本地 `env.sh` 中，Demo 结束后应及时清理
- Storage Account 已禁用公共 Blob 访问
- 最低 TLS 版本设为 1.2

## 生产环境建议

### 凭据管理
- 将 SP Secret 存入 **Azure Key Vault**，ADF 通过 Key Vault Linked Service 引用，避免明文存储
- 为 SP 设置较短的 Secret 有效期（如 90 天），配合自动轮换策略
- 使用 **Federated Identity Credentials**（Workload Identity Federation）替代 SP Secret，实现无密钥跨租户认证

### 网络安全
- 为 Storage Account 启用 **Private Endpoint**，禁用公网访问
- 配置 ADF **Managed Virtual Network** + **Private Endpoint**，确保数据传输不经公网
- 为 Storage Account 配置 **防火墙规则**，仅允许 ADF 的托管 VNet 访问

### 监控与告警
- 启用 **ADF 诊断日志**，发送到 Log Analytics Workspace
- 为 Pipeline 失败设置 **Azure Monitor 告警**（邮件/Teams 通知）
- 监控 SP Secret 到期时间，提前告警

### 数据同步策略
- 使用 **增量复制**（基于文件修改时间或 watermark）替代全量复制，降低成本和延迟
- 启用 ADF **数据流校验**（checksum/row count）确保源端和目标端数据一致
- 对关键数据启用 Storage Account 的 **Soft Delete** 和 **版本控制**，防止误删

### 高可用
- ADF 本身是托管服务，自带 HA；建议在 Pipeline 层面配置 **重试策略**（retry count + interval）
- 为 Storage Account 选择 **GRS/GZRS** 冗余级别
- 考虑使用 **ADF 的全局参数**和 **CI/CD（ARM 模板导出）** 管理多环境部署
