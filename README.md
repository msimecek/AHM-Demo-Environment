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

Run the infrastructure deployment in two stages. The first stage creates the Function Apps and leaves the OCR Function key secret update disabled; the second stage is an incremental deployment that writes the OCR Function key secret after the OCR Function host key endpoint exists. This avoids a first-deployment race where the Function App ARM resource is provisioned before its host keys are available.

```powershell
az account set --subscription <subscription-id>
Set-Location <repo-root>\src\infra
az deployment sub create --name expenseflow-demo-infra --location northeurope --template-file main.subscription.bicep --parameters main.subscription.bicepparam updateOcrFunctionKeySecret=false
az deployment sub create --name expenseflow-demo-keys --location northeurope --template-file main.subscription.bicep --parameters main.subscription.bicepparam updateOcrFunctionKeySecret=true
```

Grant package upload access if needed:

```powershell
$resourceGroupName = "<resource-group-name>"
$storageAccountName = az storage account list --resource-group $resourceGroupName --query "[0].name" --output tsv
$storageAccountId = az storage account show --resource-group $resourceGroupName --name $storageAccountName --query id --output tsv
$userObjectId = az ad signed-in-user show --query id --output tsv
az role assignment create --assignee-object-id $userObjectId --assignee-principal-type User --role "Storage Blob Data Contributor" --scope $storageAccountId
az account get-access-token --resource https://storage.azure.com/ --output none
```

### Deploy Function Apps
Use the storage-package deployment script; do not use `az functionapp deployment source config-zip` for the restricted baseline.

Generate the Health Model annotation map from Bicep deployment outputs after infra deployment, or whenever Function App or Health Model entity mappings change:

```powershell
Set-Location <repo-root>
.\scripts\Discover-HealthModelDeploymentAnnotations.ps1 -ResourceGroupName <resource-group-name>
```

If the script cannot identify the right recent subscription deployment, pass `-SubscriptionDeploymentName`.

```powershell
Set-Location <repo-root>
.\scripts\Deploy-FunctionPackages.ps1 -ResourceGroupName <resource-group-name>
```

To reuse already-built packages from `%TEMP%\expenseflow-function-packages`:

```powershell
.\scripts\Deploy-FunctionPackages.ps1 -ResourceGroupName <resource-group-name> -SkipBuild
```

The deploy script discovers the storage account and Function App names from the resource group, uploads each package as `released-package.zip`, restarts each app, syncs triggers, and prints the discovered functions.

After each Function App package deployment, the deploy script reads `.deployment\health-model-annotations.json` and uses the current Azure CLI user's management-plane bearer token to add a Health Model `Deployment` data annotation to matching Function App entities. Override the annotation values with `-DeploymentVersion`, `-DeploymentRollout`, and optional `-DeploymentAnnotationDescription`; use `-HealthModelAnnotationMapPath` to read a different generated map.

### Configure runtime behavior
The demo behavior is controlled by Function App application settings. Infrastructure deployment applies safe defaults, and you can either change those defaults in the infrastructure template before redeploying or adjust the deployed Function App configuration for temporary demo scenarios. Restart the affected Function App after changing settings so the isolated worker process reloads configuration.

| Behavior | Function App | Default | How to use it |
| --- | --- | --- | --- |
| OCR failure rate | OCR | `0` | Decimal probability from `0` to `1`; use `0.25` for roughly one failed OCR call in four, or `1` to force every OCR call to fail. |
| OCR response delay | OCR | `500` ms | Adds artificial latency before the OCR response; increase it to make downstream processing slower and make backlogs easier to observe. |
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
- OCR: `ExtractReceipt`.

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

### Notes
- With `restrictNetworkAccess = true` and `allowPublicMonitorQueryAccess = true`, Azure Monitor query access is public for the demo; ingestion and other services stay restricted.
- If `deploymentClientIpRanges` is empty, run deployment and API calls from the private network path.
- Function package containers are `function-packages-bff`, `function-packages-worker`, and `function-packages-ocr`.
