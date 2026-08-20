param(
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,
    [string] $SubscriptionDeploymentName,
    [string] $OutputPath = (Join-Path $PSScriptRoot '..\.deployment\health-model-details.json'),
    [int] $LatestDeploymentSearchLimit = 25
)

$ErrorActionPreference = 'Stop'

function Get-RequiredValue {
    param(
        [string] $Value,
        [string] $Description
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Could not determine $Description."
    }

    return $Value
}

function Assert-NativeCommandSucceeded {
    param(
        [string] $Description
    )

    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

function Get-HealthModelDetailsMapFromOutputs {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Outputs,

        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupName
    )

    if ($null -ne $Outputs.healthModelAnnotationMaps) {
        throw "Deployment outputs use the old 'healthModelAnnotationMaps' name. Rerun scripts\Deploy-Infra.ps1 with the current templates."
    }

    if ($null -eq $Outputs.healthModelDetailsMaps) {
        return $null
    }

    $maps = @($Outputs.healthModelDetailsMaps.value)

    $matchingMaps = @($maps | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.resourceGroupName) -and $_.resourceGroupName -eq $ResourceGroupName
        })

    if ($matchingMaps.Count -eq 0) {
        return $null
    }

    if ($matchingMaps.Count -gt 1) {
        throw "Deployment outputs contain multiple Health Model details maps for resource group '$ResourceGroupName'."
    }

    return $matchingMaps[0]
}

function Get-SubscriptionDeploymentOutputs {
    param(
        [string] $SubscriptionDeploymentName,
        [string] $ResourceGroupName,
        [int] $LatestDeploymentSearchLimit
    )

    if (-not [string]::IsNullOrWhiteSpace($SubscriptionDeploymentName)) {
        $deployment = az deployment sub show --name $SubscriptionDeploymentName --output json | ConvertFrom-Json
        Assert-NativeCommandSucceeded "Subscription deployment '$SubscriptionDeploymentName' lookup"
        return [pscustomobject]@{
            name = $deployment.name
            outputs = $deployment.properties.outputs
        }
    }

    $deployments = @(az deployment sub list --output json | ConvertFrom-Json)
    Assert-NativeCommandSucceeded 'Subscription deployment list'

    $candidateDeployments = @($deployments |
        Where-Object { $_.properties.provisioningState -eq 'Succeeded' } |
        Sort-Object { [datetime]$_.properties.timestamp } -Descending |
        Select-Object -First $LatestDeploymentSearchLimit)

    foreach ($candidateDeployment in $candidateDeployments) {
        $deployment = az deployment sub show --name $candidateDeployment.name --output json | ConvertFrom-Json
        Assert-NativeCommandSucceeded "Subscription deployment '$($candidateDeployment.name)' lookup"

        if ($null -ne (Get-HealthModelDetailsMapFromOutputs -Outputs $deployment.properties.outputs -ResourceGroupName $ResourceGroupName)) {
            return [pscustomobject]@{
                name = $deployment.name
                outputs = $deployment.properties.outputs
            }
        }
    }

    throw "Could not find a recent successful subscription deployment with Health Model details map outputs for resource group '$ResourceGroupName'. Pass -SubscriptionDeploymentName after redeploying the infra template."
}

function Save-HealthModelDetailsMap {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Map,

        [Parameter(Mandatory = $true)]
        [string] $OutputPath,

        [Parameter(Mandatory = $true)]
        [string] $SourceDeploymentName
    )

    $outputMap = [ordered]@{
        apiVersion = $Map.apiVersion
        generatedAt = (Get-Date).ToString('o')
        sourceDeploymentName = $SourceDeploymentName
        subscriptionId = $Map.subscriptionId
        resourceGroupName = $Map.resourceGroupName
        storageAccountName = Get-RequiredValue -Value $Map.storageAccountName -Description 'package storage account name in deployment outputs'
        healthModelResourceId = $Map.healthModelResourceId
        functionApps = @($Map.functionApps)
    }

    $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    $outputDirectory = Split-Path -Parent $resolvedOutputPath
    New-Item -ItemType Directory -Force $outputDirectory | Out-Null
    $outputMap | ConvertTo-Json -Depth 10 | Set-Content -Path $resolvedOutputPath -Encoding utf8

    Write-Host "Wrote Health Model details map to $resolvedOutputPath"
    Write-Host "Source deployment: $SourceDeploymentName"
    foreach ($functionApp in $outputMap.functionApps) {
        Write-Host "$($functionApp.name): $($functionApp.entityNames -join ', ')"
    }
}

$ResourceGroupName = Get-RequiredValue $ResourceGroupName 'resource group name'
$deploymentOutputs = Get-SubscriptionDeploymentOutputs -SubscriptionDeploymentName $SubscriptionDeploymentName -ResourceGroupName $ResourceGroupName -LatestDeploymentSearchLimit $LatestDeploymentSearchLimit
$detailsMap = Get-HealthModelDetailsMapFromOutputs -Outputs $deploymentOutputs.outputs -ResourceGroupName $ResourceGroupName

if ($null -eq $detailsMap) {
    throw "Deployment '$($deploymentOutputs.name)' does not contain Health Model details map outputs for resource group '$ResourceGroupName'."
}

Save-HealthModelDetailsMap -Map $detailsMap -OutputPath $OutputPath -SourceDeploymentName $deploymentOutputs.name
