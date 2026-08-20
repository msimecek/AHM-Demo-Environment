# Build the ExpenseFlow health model manually

A step-by-step script for a proctor who builds the model live in the Azure portal.
The result is the same model that `src/infra/modules/health-model.bicep` deploys.

## Before you start

| Item | Value |
| --- | --- |
| Prerequisite | The environment is deployed with the two repository scripts. See below. |
| Prerequisite | Function Apps run and telemetry flows. |
| Prerequisite | You have `Contributor` on the resource group. |
| Portal path | Azure portal > search `Health models` > **Create**. |

Deploy the infrastructure only. Use the deployed health model for reference.

### Deploy the environment

Always use the repository scripts. Do not deploy the Bicep files or the Function
packages by hand. The scripts handle the two-stage deployment, the generated
`.deployment\health-model-details.json` map, and the package upload.

```powershell
az account set --subscription <subscription-id>
Set-Location <repo-root>
.\scripts\Deploy-Infra.ps1 -Location northeurope
.\scripts\Deploy-FunctionPackages.ps1 -ResourceGroupName <resource-group-name>
```

If the package upload fails on access, run the second script once with
`-EnsurePackageUploadAccess`. See the [README](../README.md) for all script options.

Wait about ten minutes after the package deployment. The model needs telemetry.

### Collect these values first

Run this once and keep the output on screen. You paste these names into the log queries.

```powershell
$resourceGroupName = "<resource-group-name>"
az functionapp list --resource-group $resourceGroupName --query "[].{component:tags.component, name:name}" --output table
```

Write down:

- `<bff-function-app-name>`
- `<worker-function-app-name>`
- `<ocr-function-app-name>`

The Application Insights **role name** of each app is the same as the Function App name.

Check that telemetry arrives. Run this in Log Analytics. If it returns no rows, wait
and run it again. Without telemetry the model shows `Unknown`.

```kusto
union AppRequests, AppExceptions, AppDependencies
| where TimeGenerated > ago(15m)
| summarize records=count() by Type, AppRoleName
| order by records desc
```

### How you build the model

Build from the top down. Start with the business view, then add the layers, then add
the Azure resources under each layer. Connect each new entity to its parent
immediately after you create it. The graph grows on screen while you talk.

The finished model:

```
ExpenseFlow Application
└── Submit expenses
    ├── API layer
    │   ├── BFF
    │   │   └── BFF plan
    │   └── Data layer
    └── Processing layer
        ├── Worker
        │   └── Worker plan
        ├── OCR
        │   ├── OCR plan
        │   └── OCR provider (external)
        ├── Key Vault
        └── Data layer
            ├── Service Bus
            ├── Cosmos
            └── Storage accounts
                ├── Primary Storage
                └── Secondary Storage

Management layer
└── Keep alive func
```

`Data layer` has two parents. This is correct. Health rolls up through both paths.
`Management layer` stays separate from the application tree.

### How signal definitions work

There is no blade to create a signal definition on its own. You author the signal on the
first entity that uses it, then select **Save as signal definition**. A later entity of the
same resource type can then select that definition instead of retyping the thresholds.

| Definition | Authored on | Reused by |
| --- | --- | --- |
| 4 storage signals | `Primary Storage` (Step 7) | `Secondary Storage` |
| `ASP - Http Queue Length` | `BFF plan` (Step 7) | `Worker plan`, `OCR plan` |

---

## Step 1 — Create the health model

1. Portal > **Health models** > **Create**.
2. Subscription and resource group: the demo resource group.
3. Name: `hm-expenseflow-demo`.
4. Region: the region of the demo resources.
5. Identity: **System assigned**. Keep it on.
6. **Review + create** > **Create**.
7. Open the model > **Designer** (model editor).

### (Optional) Give the identity read access

1. Resource group > **Access control (IAM)** > **Add role assignment**.
2. Role: **Monitoring Reader**. Add **Reader** the same way.
3. Assign access to: **Managed identity** > the health model.

This can be done also while building the model in the UI.

---

## Step 2 — Root (model) entity

1. The "root" entity is added automatically.
2. Set display name: `ExpenseFlow Application`.
3. Set **Health objective** to `99.99`.
4. Save.

---

## Step 3 — Add the business layers

### 3.1 Submit expenses

1. **Add entity** > User flow.
2. Display name: `Submit expenses`. Icon: `User flow`.
3. Connect: drag from `ExpenseFlow Application` to `Submit expenses`.

### 3.2 Management layer

1. **Add entity** > System component.
2. Display name: `Management layer`. Icon: `System component`.
3. Add an unhealthy alert:
   - Severity: `Sev0`.
   - Description: `Management layer is experiencing a critical failure and requires immediate attention.`
4. Do not connect this entity. It stays outside the application tree.

---

## Step 4 — Add the three layers

Each layer entity has no Azure resource. Each aggregates the health of its children.
Icon: `System component`.

### 4.1 API layer

1. **Add entity** > System component. Display name: `API layer`.
2. Add an unhealthy alert, `Sev0`:
   `API layer is experiencing a critical failure and requires immediate attention.`
3. Connect: `Submit expenses` > `API layer`.

### 4.2 Processing layer

1. **Add entity** > System component. Display name: `Processing layer`.
2. Add an unhealthy alert, `Sev0`:
   `Processing layer is experiencing a critical failure and requires immediate attention.`
3. Connect: `Submit expenses` > `Processing layer`.

### 4.3 Data layer

1. **Add entity** > System component. Display name: `Data layer`.
2. No alert.
3. Connect twice: `API layer` > `Data layer`, and `Processing layer` > `Data layer`.

---

## Step 5 — Add the compute entities

Each Function App entity has two signal groups: an Azure resource group and a Log
Analytics group. Set **Azure Resource Health** to **Disabled** on all four Function App
entities.

In every query below, replace the placeholder with the Function App name you collected.
The name is case sensitive.

### 5.1 BFF

1. **Add entity** > **Azure resource** > the **BFF** Function App.
2. Display name: `BFF`. Icon: `Resource`. Resource Health: **Disabled**.
3. Add a **Log Analytics query** signal:
   - Workspace: the demo Log Analytics workspace.
   - Display name: `Number of exceptions`.
   - Value column: `exceptions`.
   - Refresh: 1 minute. Time grain: 30 minutes.
   - Degraded: Greater than `0`. Unhealthy: Greater than `0`.

```kusto
AppExceptions
| where TimeGenerated > ago(10m)
| where AppRoleName == "<bff-function-app-name>"
| summarize exceptions=count()
```

4. Connect: `API layer` > `BFF`.

### 5.2 Worker

1. **Add entity** > **Azure resource** > the **Worker** Function App.
2. Display name: `Worker`. Resource Health: **Disabled**.
3. Log Analytics signal 1:
   - Display name: `OCR failures`. Value column: `failures`.
   - Refresh: 1 minute. Time grain: 30 minutes.
   - Degraded: Greater than `0`. Unhealthy: Greater than `5`.

```kusto
AppDependencies
| where TimeGenerated > ago(10m)
| where AppRoleName == "<worker-function-app-name>"
| where Name contains "/api/ocr/extract"
| summarize calls=count(), failures=countif(Success == false), p95DurationMs=percentile(DurationMs, 95) by TimeGenerated=bin(TimeGenerated, 5m), DependencyType, Target, Name
| order by TimeGenerated desc
```

4. Log Analytics signal 2:
   - Display name: `Worker executions`. Value column: `executions`.
   - Refresh: 1 minute. Time grain: 30 minutes.
   - Unhealthy: Less than `1`. No degraded rule.

```kusto
AppRequests
| where TimeGenerated > ago(10m)
| where AppRoleName == "<worker-function-app-name>"
| where Name == "ProcessExpense"
| summarize
    executions=count(),
    failures=countif(Success == false),
    avgDurationMs=avg(DurationMs),
    p95DurationMs=percentile(DurationMs, 95)
    by bin(TimeGenerated, 5m)
| order by TimeGenerated desc
| take 1
```

5. Connect: `Processing layer` > `Worker`.

### 5.3 OCR

1. **Add entity** > **Azure resource** > the **OCR** Function App.
2. Display name: `OCR`. Resource Health: **Disabled**.
3. Log Analytics signal:
   - Display name: `OCR duration`. Value column: `avgDurationMs`. Unit: `ms`.
   - Refresh: 1 minute. Time grain: 30 minutes.
   - Degraded: Greater than `1000`. Unhealthy: Greater than `2000`.

```kusto
AppRequests
| where TimeGenerated > ago(10m)
| where AppRoleName == "<ocr-function-app-name>"
| where Name == "ExtractReceipt"
| summarize
    executions=count(),
    failures=countif(Success == false),
    avgDurationMs=avg(DurationMs),
    p95DurationMs=percentile(DurationMs, 95)
    by bin(TimeGenerated, 5m)
| order by TimeGenerated desc
| take 1
```

4. Connect: `Processing layer` > `OCR`.

### 5.4 Keep alive func

1. **Add entity** > **Azure resource** > the **BFF** Function App again.
2. Display name: `Keep alive func`. Resource Health: **Disabled**.
3. Add one metric signal:

| Field | Value |
| --- | --- |
| Display name | `On Demand Function Execution Count` |
| Namespace | `microsoft.web/sites` |
| Metric | `OnDemandFunctionExecutionCount` |
| Aggregation | Count |
| Time grain | 5 minutes |
| Degraded | Less than `2` |
| Unhealthy | Less than `1` |

4. Connect: `Management layer` > `Keep alive func`.

Two entities point at the same Function App. An entity is a view of a resource, not the
resource itself.

### 5.5 Key Vault

1. **Add entity** > **Azure resource** > the Key Vault.
2. Display name: `Key Vault`. Resource Health: **Enabled**.
3. Add two metric signals, namespace `microsoft.keyvault/vaults`:

| Display name | Metric | Aggregation | Grain | Degraded | Unhealthy |
| --- | --- | --- | --- | --- | --- |
| `Overall Vault Availability` | `Availability` | Average | 30 min | < `99` % | < `95` % |
| `Overall Service Api Latency` | `ServiceApiLatency` | Average | 15 min | > `50` ms | > `100` ms |

4. Connect: `Processing layer` > `Key Vault`.

---

## Step 6 — Add the data services

### 6.1 Service Bus

1. **Add entity** > **Azure resource** > the Service Bus namespace.
2. Display name: `Service Bus`. Resource Health: **Enabled**.
3. Add three metric signals, namespace `microsoft.servicebus/namespaces`:

| Display name | Metric | Aggregation | Grain | Degraded | Unhealthy |
| --- | --- | --- | --- | --- | --- |
| `CPU` | `NamespaceCpuUsage` | Maximum | 5 min | > `20` % | > `50` % |
| `Count of active messages in a Queue/Topic.` | `ActiveMessages` | Maximum | 1 min | > `5` | > `10` |
| `Abandoned Messages` | `AbandonMessage` | Total | 1 min | none | > `0` |

4. Connect: `Data layer` > `Service Bus`.

> This is the backlog demo signal. Raise the worker delay later and this entity turns red.

### 6.2 Cosmos

1. **Add entity** > **Azure resource** > the Cosmos DB account.
2. Display name: `Cosmos`. Resource Health: **Enabled**.
3. Add four metric signals, namespace `microsoft.documentdb/databaseaccounts`:

| Display name | Metric | Aggregation | Grain | Degraded | Unhealthy |
| --- | --- | --- | --- | --- | --- |
| `Service Availability` | `ServiceAvailability` | Average | 1 hour | < `95` % | < `90` % |
| `Total Requests` | `TotalRequests` | Count | 5 min | < `2` | equal `0` |
| `Server Side Latency Direct` | `ServerSideLatencyDirect` | Average | 5 min | > `20` ms | > `200` ms |
| `Normalized RU Consumption` | `NormalizedRUConsumption` | Maximum | 5 min | > `70` % | > `90` % |

For `Server Side Latency Direct` set the dimension filter `OperationType eq 'Upsert'`.

4. Connect: `Data layer` > `Cosmos`.

### 6.3 Storage accounts

1. **Add entity** > entity without an Azure resource.
2. Display name: `Storage accounts`. Icon: `Generic`.
3. Open the **dependencies** signal group and set:

| Field | Value |
| --- | --- |
| Aggregation type | `MinHealthy` |
| Unit | Absolute |
| Degraded threshold | `1` |
| Unhealthy threshold | `0` |
| Ignore unknown | No |

4. Connect: `Data layer` > `Storage accounts`.

One healthy child keeps this group degraded. Zero healthy children makes it unhealthy.
Every other group entity uses the default aggregation.

---

## Step 7 — Add the leaf resources

This is the most technical layer. You author the two reusable signal definitions here.

### 7.1 Primary Storage

1. **Add entity** > **Azure resource** > the **primary storage account**.
2. Display name: `Primary Storage`. Icon: `Resource`. Resource Health: **Enabled**.
3. Add the four metric signals below. Namespace is `microsoft.storage/storageaccounts`
   for all four. Refresh 1 minute. After each one, select **Save as signal definition**
   and use the display name as the definition name.
4. Connect: `Storage accounts` > `Primary Storage`.

#### Signal `Client/auth errors`

| Field | Value |
| --- | --- |
| Metric | `Transactions` |
| Dimension filter | `ResponseType eq 'ClientOtherError'` |
| Aggregation | Total |
| Time grain | 5 minutes |
| Unit | Count |
| Degraded | Greater than `5` |
| Unhealthy | Greater than `25` |

#### Signal `AuthorizationError Transations`

| Field | Value |
| --- | --- |
| Metric | `Transactions` |
| Dimension filter | `ResponseType eq 'AuthorizationError'` |
| Aggregation | Total |
| Time grain | 5 minutes |
| Unit | Count |
| Degraded | Greater than `0` |
| Unhealthy | Greater than `5` |

#### Signal `Success E2E Latency`

| Field | Value |
| --- | --- |
| Metric | `SuccessE2ELatency` |
| Aggregation | Average |
| Time grain | 5 minutes |
| Unit | Milliseconds |
| Degraded | Greater than `100` |
| Unhealthy | Greater than `200` |

#### Signal `Availability`

| Field | Value |
| --- | --- |
| Metric | `Availability` |
| Aggregation | Minimum |
| Time grain | 5 minutes |
| Unit | Percent |
| Degraded | Less than `95` |
| Unhealthy | Less than `90` |

### 7.2 Secondary Storage

1. **Add entity** > **Azure resource** > the **secondary storage account**.
2. Display name: `Secondary Storage`. Resource Health: **Enabled**.
3. Add signals from the **existing signal definitions**. Select all four definitions
   you saved in Step 7.1. Do not retype the thresholds.
4. Connect: `Storage accounts` > `Secondary Storage`.

### 7.3 BFF plan

1. **Add entity** > **Azure resource** > the **BFF** Flex Consumption plan.
2. Display name: `BFF plan`. Resource Health: **Disabled**.
3. Add one metric signal:

| Field | Value |
| --- | --- |
| Display name | `ASP - Http Queue Length` |
| Namespace | `microsoft.web/serverfarms` |
| Metric | `HttpQueueLength` |
| Aggregation | Average |
| Time grain | 1 minute |
| Refresh | 1 minute |
| Unit | Count |
| Degraded | Greater than `10` |
| Unhealthy | Greater than `50` |

4. Select **Save as signal definition**. Name it `ASP - Http Queue Length`.
5. Connect: `BFF` > `BFF plan`.

### 7.4 Worker plan and OCR plan

Create two more entities. Each reuses the `ASP - Http Queue Length` definition.
Refresh 1 minute. Resource Health: **Disabled**.

| Display name | Azure resource | Connect from |
| --- | --- | --- |
| `Worker plan` | Worker Flex Consumption plan | `Worker` |
| `OCR plan` | OCR Flex Consumption plan | `OCR` |

### 7.5 OCR provider (external)

1. **Add entity** > entity without an Azure resource.
2. **Name**: `external-ocr-provider`. Use this exact name. The Function code sends
   reports to it.
3. Display name: `OCR provider (external)`. Icon: `Generic`.
4. Tags:
   - `component` = `external-ocr-provider`
   - `signalName` = `external-ocr-provider-availability`
5. Add no signals. The application creates the signal at run time.
6. Connect: `OCR` > `OCR provider (external)`.

This entity has no Azure resource. The OCR Function pushes its state through the
`ingestHealthReport` API. If reports stop for two minutes, the entity becomes
`Unknown`, not `Unhealthy`.

---

## Step 8 — Add the discovery rule

1. Model editor > **Discovery rules** > **Add**.
2. Name: `regional-policy-config`.
3. Display name: `Regional configuration stores`.
4. Authentication: the system-assigned setting.
5. Kind: **Resource Graph query**.
6. Discover relationships: **Enabled**.
7. Add recommended signals: **Enabled**.
8. Add Resource Health signal: **Disabled**.
9. Query:

```kusto
resources
| where type =~ 'microsoft.appconfiguration/configurationstores' and tags['component'] =~ 'policy-config'
```

Discovery runs about every five minutes. Tagged App Configuration stores appear on
their own. You author nothing for them.

---

## Make the model change state on stage

Run these after the model is built. Wait one to three minutes for each effect.

Slow the worker and grow the Service Bus backlog:

```powershell
.\scripts\Set-DemoBehavior.ps1 -ResourceGroupName <resource-group-name> -WorkerProcessingDelayMs 5000 -KeepAliveBatchSize 5
```

Make OCR fail and turn the `Worker` entity red:

```powershell
.\scripts\Set-DemoBehavior.ps1 -ResourceGroupName <resource-group-name> -OcrFailureRate 1
```

Push an unhealthy external report:

```powershell
.\scripts\Set-DemoBehavior.ps1 -ResourceGroupName <resource-group-name> -ExternalOcrProviderReportProbability 1 -ExternalOcrProviderHealth Unhealthy
```

Reset everything:

```powershell
.\scripts\Set-DemoBehavior.ps1 -ResourceGroupName <resource-group-name> -OcrFailureRate 0 -WorkerProcessingDelayMs 1000 -KeepAliveBatchSize 1 -ExternalOcrProviderReportProbability 0.35 -ExternalOcrProviderHealth Healthy
```

---

## Final checklist

- [ ] 20 entities exist. The graph matches the tree above.
- [ ] 19 connections exist. `Data layer` has two parents.
- [ ] 5 signal definitions exist and are reused as shown in the table above.
- [ ] The root entity is `ExpenseFlow Application`, objective `99.99`.
- [ ] The model identity has `Monitoring Reader` and `Reader` on the resource group.
- [ ] No entity stays `Unknown` after five minutes, except `OCR provider (external)` before the first report.
- [ ] The discovery rule shows at least three App Configuration stores after five minutes.
- [ ] Three Sev0 alerts exist on the layer entities.

## If a signal shows Unknown

| Cause | Fix |
| --- | --- |
| Missing role assignment | Add `Monitoring Reader` and `Reader` to the model identity. |
| Wrong `AppRoleName` | Compare it with the Function App name. It is case sensitive. |
| No telemetry | Run the telemetry check in "Collect these values first". Confirm the keep-alive timer is enabled. |
| Wrong value column | The column name must match the query output exactly. |
| Expired report | The external entity becomes `Unknown` two minutes after the last report. |
