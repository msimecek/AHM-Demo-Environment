param(
    [string] $Location = 'northeurope',
    [string] $TemplateFile = (Join-Path $PSScriptRoot '..\src\infra\main.subscription.bicep'),
    [string] $ParametersFile = (Join-Path $PSScriptRoot '..\src\infra\main.subscription.bicepparam'),
    [string] $InfraDeploymentName = 'expenseflow-demo-infra',
    [string] $KeysDeploymentName = 'expenseflow-demo-keys'
)

$ErrorActionPreference = 'Stop'

function Assert-NativeCommandSucceeded {
    param(
        [string] $Description
    )

    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

$resolvedTemplateFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TemplateFile)
$resolvedParametersFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ParametersFile)

if (-not (Test-Path $resolvedTemplateFile)) {
    throw "Infrastructure template not found: $resolvedTemplateFile"
}

if (-not (Test-Path $resolvedParametersFile)) {
    throw "Infrastructure parameters file not found: $resolvedParametersFile"
}

Write-Host 'Deploying infrastructure without the OCR Function key secret update...'
az deployment sub create `
    --name $InfraDeploymentName `
    --location $Location `
    --template-file $resolvedTemplateFile `
    --parameters $resolvedParametersFile `
    --parameters updateOcrFunctionKeySecret=false `
    --output none
Assert-NativeCommandSucceeded "Subscription deployment '$InfraDeploymentName'"

Write-Host 'Updating the OCR Function key secret...'
az deployment sub create `
    --name $KeysDeploymentName `
    --location $Location `
    --template-file $resolvedTemplateFile `
    --parameters $resolvedParametersFile `
    --parameters updateOcrFunctionKeySecret=true `
    --output none
Assert-NativeCommandSucceeded "Subscription deployment '$KeysDeploymentName'"

$resourceGroupNames = @((az deployment sub show `
        --name $KeysDeploymentName `
        --query 'properties.outputs.resourceGroupNames.value[]' `
    --output tsv) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
Assert-NativeCommandSucceeded 'Deployed resource group discovery'

if ($resourceGroupNames.Count -ne 1) {
    throw "Expected one deployed resource group, but found $($resourceGroupNames.Count)."
}

& (Join-Path $PSScriptRoot 'Discover-HealthModelDeploymentAnnotations.ps1') `
    -ResourceGroupName $resourceGroupNames[0] `
    -SubscriptionDeploymentName $KeysDeploymentName

Write-Host 'Infrastructure deployment complete.'