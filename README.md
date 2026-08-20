# Azure Monitor health models demo environment

## Purpose
A self-contained demo environment for [Azure Monitor health models](https://learn.microsoft.com/azure/azure-monitor/health-models/overview). It provisions a set of Azure resources, defines a health model over them, and provides a small control panel to trigger health-state changes for demonstration.

## Goals
- Show how a health model is authored and deployed alongside infrastructure.
- Demonstrate health-state propagation across related resources.
- Allow live, on-demand manipulation of signals (health states, queue messages).
- Be fully deployable into a restricted enterprise environment.

## Non-Goals
- Production-grade workloads or scale.
- Comprehensive coverage of every Azure resource type.
- Long-running or stateful business logic beyond what the demo needs.

## How to use

### Prerequisites
- PowerShell, Azure CLI, .NET SDK 10.
- Azure CLI signed in to the target subscription.
- The deploying identity must have ARM rights for the resource group and `Storage Blob Data Contributor` on the demo storage account.
- If running from a dev machine while `restrictNetworkAccess = true`, add the machine's outbound public IP to the deployment parameters.

### Deploy infrastructure
Copy the example deployment parameters to a local parameter file before deploying, then set the target resource group, Azure region, deployment client IP ranges, and network access flags for your environment.

Run the infrastructure deployment script. It deploys in two stages to avoid a first-deployment race with the OCR Function host key, then generates `.deployment\health-model-details.json` for the Function App package deployment.

```powershell
az account set --subscription <subscription-id>
Set-Location <repo-root>
.\scripts\Deploy-Infra.ps1 -Location northeurope
```

Grant package upload access if needed:

```powershell
$resourceGroupName = "<resource-group-name>"
.\scripts\Deploy-FunctionPackages.ps1 -ResourceGroupName $resourceGroupName -EnsurePackageUploadAccess
```

### Deploy Function Apps
Use the storage-package deployment script; do not use `az functionapp deployment source config-zip` for the restricted baseline.

```powershell
Set-Location <repo-root>
.\scripts\Deploy-FunctionPackages.ps1 -ResourceGroupName <resource-group-name>
```

To reuse already-built packages from `%TEMP%\expenseflow-function-packages`:

```powershell
.\scripts\Deploy-FunctionPackages.ps1 -ResourceGroupName <resource-group-name> -SkipBuild
```

The deploy script reads the package storage account from `.deployment\health-model-details.json`, discovers the Function App names from the resource group, uploads each package as `released-package.zip`, restarts each app, syncs triggers, and prints the discovered functions. Pass `-StorageAccountName` to override the generated value.

If package upload access is missing, pass `-EnsurePackageUploadAccess` to have the script assign the required storage data role to the signed-in Azure CLI user before uploading packages. The signed-in user must have role assignment permissions on the storage account.

After each Function App package deployment, the deploy script reads `.deployment\health-model-details.json` and uses the current Azure CLI user's management-plane bearer token to add a Health Model `Deployment` data annotation to matching Function App entities. Override the annotation values with `-DeploymentVersion`, `-DeploymentRollout`, and optional `-DeploymentAnnotationDescription`; use `-HealthModelDetailsMapPath` to read a different generated map.

### Configure runtime behavior
The demo behavior is controlled by Function App application settings. Infrastructure deployment applies safe defaults, and you can either change those defaults in the infrastructure template before redeploying or adjust the deployed Function App configuration for temporary demo scenarios. Restart the affected Function App after changing settings so the isolated worker process reloads configuration.

| Behavior | Function App | Default | How to use it |
| --- | --- | --- | --- |
| OCR failure rate | OCR | `0` | Decimal probability from `0` to `1`; use `0.25` for roughly one failed OCR call in four, or `1` to force every OCR call to fail. |
| OCR response delay | OCR | `500` ms | Adds artificial latency before the OCR response; increase it to make downstream processing slower and make backlogs easier to observe. |
| External OCR provider heartbeat | OCR | enabled, every 10 seconds | Attempts to report the configured external provider health to the Health Model on each timer run. |
| External OCR provider report probability | OCR | `0.35` | Decimal probability from `0` to `1`; use `1` to send on every heartbeat during a demo. |
| External OCR provider health | OCR | `Healthy` | Health state sent by the reporter. Valid values are `Healthy`, `Degraded`, `Unhealthy`, and `Unknown`. |
| External OCR provider report expiry | OCR | `2` minutes | If no new report arrives before expiry, the external provider entity becomes `Unknown`; expiry does not make it `Unhealthy`. |
| Worker processing delay | Worker | `1000` ms | Adds artificial latency before each queued expense is processed; increase it to grow queue depth without making OCR fail. |
| Keep-alive submissions | BFF | enabled | Periodically creates synthetic expenses so the environment keeps producing telemetry even when nobody is actively using the API. |
| Keep-alive interval | BFF | every 30 seconds | Uses the Azure Functions timer schedule format; make it less frequent to reduce background traffic or more frequent to create continuous load. |
| Keep-alive batch size | BFF | `1` | Controls how many synthetic expenses each keep-alive run creates; increase it to drive more queue and storage activity. |

For a one-off demo change, discover the target Function App and set the relevant app setting with Azure CLI:

```powershell
$resourceGroupName = "<resource-group-name>"
$ocrFunctionAppName = az functionapp list --resource-group $resourceGroupName --query "[?tags.component=='ocr'].name | [0]" --output tsv
az functionapp config appsettings set --resource-group $resourceGroupName --name $ocrFunctionAppName --settings "<ocr-failure-rate-setting>=0.25"
az functionapp restart --resource-group $resourceGroupName --name $ocrFunctionAppName
```

Use the same pattern for the BFF and Worker settings. Optional numeric and Boolean settings fall back to their defaults when omitted or invalid, so prefer simple values such as whole milliseconds, `true`/`false`, and decimal probabilities.

### Verify deployment
```powershell
$resourceGroupName = "<resource-group-name>"
az functionapp list --resource-group $resourceGroupName --query "[].{name:name,state:state}" --output table
$bffFunctionAppName = az functionapp list --resource-group $resourceGroupName --query "[?tags.component=='bff'].name | [0]" --output tsv
$workerFunctionAppName = az functionapp list --resource-group $resourceGroupName --query "[?tags.component=='worker'].name | [0]" --output tsv
$ocrFunctionAppName = az functionapp list --resource-group $resourceGroupName --query "[?tags.component=='ocr'].name | [0]" --output tsv
az functionapp function list --resource-group $resourceGroupName --name $bffFunctionAppName --query "[].name" --output table
az functionapp function list --resource-group $resourceGroupName --name $workerFunctionAppName --query "[].name" --output table
az functionapp function list --resource-group $resourceGroupName --name $ocrFunctionAppName --query "[].name" --output table
```

Expected functions:
- BFF: `SubmitSyntheticExpense`, `KeepAlive`.
- Worker: `ProcessExpense`.
- OCR: `ExtractReceipt`, `ExternalOcrProviderHeartbeat`.

### API usage
Get Function keys once per environment and keep them locally:

```powershell
$resourceGroupName = "<resource-group-name>"
$bffFunctionAppName = az functionapp list --resource-group $resourceGroupName --query "[?tags.component=='bff'].name | [0]" --output tsv
$ocrFunctionAppName = az functionapp list --resource-group $resourceGroupName --query "[?tags.component=='ocr'].name | [0]" --output tsv
$submitKey = az functionapp function keys list --resource-group $resourceGroupName --name $bffFunctionAppName --function-name SubmitSyntheticExpense --query default --output tsv
$ocrKey = az functionapp function keys list --resource-group $resourceGroupName --name $ocrFunctionAppName --function-name ExtractReceipt --query default --output tsv
```

Submit a synthetic expense:

```powershell
Invoke-RestMethod -Method Post -Uri "https://$bffFunctionAppName.azurewebsites.net/api/expenses/synthetic?code=$submitKey" -ContentType "application/json" -Body "{}"
```

REST request:

```http
POST https://<bff-function-app-name>.azurewebsites.net/api/expenses/synthetic?code=<submit-function-key>
Content-Type: application/json

{}
```

Response:

```json
{
  "ExpenseId": "exp-20260708094119374-6731",
  "ReceiptBlobName": "2026/07/08/exp-20260708094119374-6731.json",
  "Vendor": "Contoso Travel",
  "Amount": 381.63,
  "Currency": "EUR",
  "Category": "Office",
  "SubmittedAt": "2026-07-08T11:41:19.3750103+02:00"
}
```

Check queue drain:

```powershell
$serviceBusNamespaceName = az servicebus namespace list --resource-group $resourceGroupName --query "[?tags.workload=='expenseflow'].name | [0]" --output tsv
az servicebus queue show --resource-group $resourceGroupName --namespace-name $serviceBusNamespaceName --name expenses --query "{active:countDetails.activeMessageCount, deadletter:countDetails.deadLetterMessageCount}" --output table
```

Call OCR directly for test only, using a receipt blob name returned by synthetic submission:

```powershell
$body = @{
    expenseId = "exp-20260708094119374-6731"
    tenantId = "demo"
    receiptBlobName = "2026/07/08/exp-20260708094119374-6731.json"
} | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri "https://$ocrFunctionAppName.azurewebsites.net/api/ocr/extract?code=$ocrKey" -ContentType "application/json" -Body $body
```

REST request:

```http
POST https://<ocr-function-app-name>.azurewebsites.net/api/ocr/extract?code=<ocr-function-key>
Content-Type: application/json

{
  "expenseId": "exp-20260708094119374-6731",
  "tenantId": "demo",
  "receiptBlobName": "2026/07/08/exp-20260708094119374-6731.json"
}
```

OCR response:

```json
{
  "ExpenseId": "exp-20260708094119374-6731",
  "Vendor": "Contoso Travel",
  "Amount": 381.63,
  "Currency": "EUR",
  "Category": "Office",
  "Confidence": 0.95,
  "ProcessedAt": "2026-07-08T09:41:22.1234567+00:00"
}
```

### External health reporter demo
The OCR Function simulates an external OCR provider that reports its own health through the Health Model `ingestHealthReport` API. A dedicated user-assigned managed identity is attached to the OCR Function and granted `Contributor` on the Health Model. The reporter targets the `OCR provider (external)` entity and sends the health state configured in `ExpenseFlow__ExternalOcrProviderHealth`.

The reporter does not inspect OCR failures or automatically choose `Unhealthy`. To force an unhealthy report for a demo, set the report probability to `1`, set the state to `Unhealthy`, and restart the OCR Function App:

```powershell
$resourceGroupName = "<resource-group-name>"
$ocrFunctionAppName = az functionapp list --resource-group $resourceGroupName --query "[?tags.component=='ocr'].name | [0]" --output tsv
az functionapp config appsettings set --resource-group $resourceGroupName --name $ocrFunctionAppName --settings ExpenseFlow__ExternalOcrProviderHeartbeatSendProbability=1 ExpenseFlow__ExternalOcrProviderHealth=Unhealthy
az functionapp restart --resource-group $resourceGroupName --name $ocrFunctionAppName
```

Restore healthy probabilistic reporting after the demo:

```powershell
az functionapp config appsettings set --resource-group $resourceGroupName --name $ocrFunctionAppName --settings ExpenseFlow__ExternalOcrProviderHeartbeatSendProbability=0.35 ExpenseFlow__ExternalOcrProviderHealth=Healthy
az functionapp restart --resource-group $resourceGroupName --name $ocrFunctionAppName
```

With the default 10-second schedule and `0.35` probability, some successful timer invocations intentionally skip sending a report. If reports stop for more than two minutes, the entity changes to `Unknown` when the last report expires.

### Health model auto-discovery demo
The health model includes a scoped Azure Resource Graph discovery rule (`regional-policy-config`) that automatically adds **App Configuration** stores tagged `component=policy-config` as monitored entities. These stores represent per-region ExpenseFlow expense policy and are provisioned as a fleet (one per Azure region) separate from the hand-authored entities.

Deployment provisions three regional stores by default. Discovery runs about every five minutes, so newly added or removed tagged stores are reflected automatically with recommended signals and an Azure Resource Health signal.

List the discovered stores:

```powershell
$resourceGroupName = "<resource-group-name>"
az appconfig list --resource-group $resourceGroupName --query "[?tags.component=='policy-config'].{name:name, region:tags.region, location:location}" --output table
```

To demonstrate live auto-discovery, set `enableDemoPolicyConfigRegion = true` in `main.subscription.bicepparam` (or pass it on the command line) and redeploy. This provisions one additional regional store, which the health model discovers within a few minutes:

```powershell
az deployment sub create --name expenseflow-demo-infra --location northeurope --template-file main.subscription.bicep --parameters main.subscription.bicepparam enableDemoPolicyConfigRegion=true
```

### Notes
- With `restrictNetworkAccess = true` and `allowPublicMonitorQueryAccess = true`, Azure Monitor query access is public for the demo; ingestion and other services stay restricted.
- If `deploymentClientIpRanges` is empty, run deployment and API calls from the private network path.
- Function package containers are `function-packages-bff`, `function-packages-worker`, and `function-packages-ocr`.
- The regional policy config stores use App Configuration Free tier (one store per Azure region) and are public-endpoint only; they exist purely as auto-discovery filler and sit outside the locked-down data path.
- `healthModelName` is optional; leave it empty to auto-generate the health model resource name.
