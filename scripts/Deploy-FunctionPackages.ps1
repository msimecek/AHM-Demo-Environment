param(
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,
    [string] $StorageAccountName,
    [string] $BffFunctionAppName,
    [string] $WorkerFunctionAppName,
    [string] $OcrFunctionAppName,
    [string] $Configuration = 'Release',
    [string] $ArtifactsPath = (Join-Path $env:TEMP 'expenseflow-function-packages'),
    [string] $HealthModelAnnotationMapPath = (Join-Path $PSScriptRoot '..\.deployment\health-model-annotations.json'),
    [string] $DeploymentVersion = "v$((Get-Date).ToString('yyyy.M.d'))",
    [string] $DeploymentRollout = (Get-Date).ToString('yyyyMMddHHmmss'),
    [string] $DeploymentAnnotationDescription,
    [switch] $SkipHealthModelAnnotation,
    [switch] $SkipBuild
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

function Get-StorageAccountName {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupName
    )

    $accounts = @(az storage account list --resource-group $ResourceGroupName --output json | ConvertFrom-Json)
    Assert-NativeCommandSucceeded 'Storage account discovery'

    $matchingAccounts = @($accounts | Where-Object { $_.tags.workload -eq 'expenseflow' })

    if ($matchingAccounts.Count -eq 0) {
        throw "Could not find an ExpenseFlow storage account in resource group '$ResourceGroupName'. Pass -StorageAccountName explicitly."
    }

    if ($matchingAccounts.Count -gt 1) {
        $accountNames = ($matchingAccounts | ForEach-Object { $_.name }) -join ', '
        throw "Found multiple ExpenseFlow storage accounts in resource group '$ResourceGroupName': $accountNames. Pass -StorageAccountName explicitly."
    }

    return $matchingAccounts[0].name
}

function Get-ManagementAccessToken {
    $accessToken = az account get-access-token --resource https://management.azure.com/ --query accessToken --output tsv
    Assert-NativeCommandSucceeded 'Azure management access token acquisition'
    return Get-RequiredValue $accessToken 'Azure management access token'
}

function Get-HealthModelAnnotationMap {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not (Test-Path $resolvedPath)) {
        throw "Health Model annotation map not found: $resolvedPath. Run scripts\Discover-HealthModelDeploymentAnnotations.ps1 first, or pass -SkipHealthModelAnnotation."
    }

    $map = Get-Content $resolvedPath -Raw | ConvertFrom-Json

    if ([string]::IsNullOrWhiteSpace($map.healthModelResourceId)) {
        throw "Health Model annotation map '$resolvedPath' does not contain healthModelResourceId."
    }

    if ($null -eq $map.functionApps) {
        throw "Health Model annotation map '$resolvedPath' does not contain functionApps."
    }

    return $map
}

function Get-HealthModelAnnotationEntityNames {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Map,

        [Parameter(Mandatory = $true)]
        [string] $AppName,

        [Parameter(Mandatory = $true)]
        [string] $ResourceId,

        [Parameter(Mandatory = $true)]
        [string] $Component
    )

    $normalizedResourceId = $ResourceId.ToLowerInvariant()
    $matches = @($Map.functionApps | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.resourceId) -and $_.resourceId.ToLowerInvariant() -eq $normalizedResourceId
        })

    if ($matches.Count -eq 0) {
        $matches = @($Map.functionApps | Where-Object { $_.name -eq $AppName })
    }

    if ($matches.Count -eq 0) {
        $matches = @($Map.functionApps | Where-Object { $_.component -eq $Component })
    }

    if ($matches.Count -eq 0) {
        throw "Health Model annotation map does not contain entities for Function App '$AppName' ($ResourceId)."
    }

    if ($matches.Count -gt 1) {
        throw "Health Model annotation map contains multiple entries for Function App '$AppName' ($ResourceId)."
    }

    $entityNames = @($matches[0].entityNames)
    if ($entityNames.Count -eq 0) {
        throw "Health Model annotation map entry for Function App '$AppName' has no entityNames."
    }

    return $entityNames
}

function Add-HealthModelDeploymentAnnotation {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ModelRoot,

        [Parameter(Mandatory = $true)]
        [string] $EntityName,

        [Parameter(Mandatory = $true)]
        [string] $DeploymentVersion,

        [Parameter(Mandatory = $true)]
        [string] $DeploymentRollout,

        [string] $Description,

        [Parameter(Mandatory = $true)]
        [string] $AccessToken
    )

    $body = [ordered]@{
        annotationDetails = [ordered]@{
            type = 'Deployment'
            version = $DeploymentVersion
            rollout = $DeploymentRollout
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Description)) {
        $body.description = $Description
    }

    $escapedEntityName = [Uri]::EscapeDataString($EntityName)
    $url = "https://management.azure.com$ModelRoot/entities/$escapedEntityName/addDataAnnotation?api-version=2026-05-01-preview"
    Invoke-RestMethod `
        -Method Post `
        -Uri $url `
        -Headers @{
            Authorization = "Bearer $AccessToken"
            'Content-Type' = 'application/json'
        } `
        -Body ($body | ConvertTo-Json -Depth 10) | Out-Null
}

$repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

if ([string]::IsNullOrWhiteSpace($StorageAccountName)) {
    $StorageAccountName = Get-StorageAccountName -ResourceGroupName $ResourceGroupName
}

if ([string]::IsNullOrWhiteSpace($BffFunctionAppName)) {
    $BffFunctionAppName = az functionapp list --resource-group $ResourceGroupName --query "[?tags.component=='bff'].name | [0]" --output tsv
    Assert-NativeCommandSucceeded 'BFF Function App discovery'
}

if ([string]::IsNullOrWhiteSpace($WorkerFunctionAppName)) {
    $WorkerFunctionAppName = az functionapp list --resource-group $ResourceGroupName --query "[?tags.component=='worker'].name | [0]" --output tsv
    Assert-NativeCommandSucceeded 'Worker Function App discovery'
}

if ([string]::IsNullOrWhiteSpace($OcrFunctionAppName)) {
    $OcrFunctionAppName = az functionapp list --resource-group $ResourceGroupName --query "[?tags.component=='ocr'].name | [0]" --output tsv
    Assert-NativeCommandSucceeded 'OCR Function App discovery'
}

$StorageAccountName = Get-RequiredValue $StorageAccountName 'storage account name'
$BffFunctionAppName = Get-RequiredValue $BffFunctionAppName 'BFF Function App name'
$WorkerFunctionAppName = Get-RequiredValue $WorkerFunctionAppName 'Worker Function App name'
$OcrFunctionAppName = Get-RequiredValue $OcrFunctionAppName 'OCR Function App name'

$apps = @(
    @{
        Name = $BffFunctionAppName
        Project = Join-Path $repositoryRoot 'src\app\ExpenseFlow.Bff\ExpenseFlow.Bff.csproj'
        Container = 'function-packages-bff'
        ArtifactName = 'bff'
    },
    @{
        Name = $WorkerFunctionAppName
        Project = Join-Path $repositoryRoot 'src\app\ExpenseFlow.Worker\ExpenseFlow.Worker.csproj'
        Container = 'function-packages-worker'
        ArtifactName = 'worker'
    },
    @{
        Name = $OcrFunctionAppName
        Project = Join-Path $repositoryRoot 'src\app\ExpenseFlow.Ocr\ExpenseFlow.Ocr.csproj'
        Container = 'function-packages-ocr'
        ArtifactName = 'ocr'
    }
)

New-Item -ItemType Directory -Force $ArtifactsPath | Out-Null

if (-not $SkipBuild) {
    foreach ($app in $apps) {
        $publishPath = Join-Path $ArtifactsPath $app.ArtifactName
        $zipPath = Join-Path $ArtifactsPath "$($app.ArtifactName).zip"

        Remove-Item -Recurse -Force $publishPath -ErrorAction SilentlyContinue
        dotnet publish $app.Project --configuration $Configuration --output $publishPath --nologo --verbosity minimal
        Assert-NativeCommandSucceeded "$($app.ArtifactName) publish"
        Compress-Archive -Path "$publishPath\*" -DestinationPath $zipPath -Force
        $app.ZipPath = $zipPath
    }
}
else {
    foreach ($app in $apps) {
        $zipPath = Join-Path $ArtifactsPath "$($app.ArtifactName).zip"
        if (-not (Test-Path $zipPath)) {
            throw "Package not found: $zipPath"
        }

        $app.ZipPath = $zipPath
    }
}

az account get-access-token --resource https://storage.azure.com/ --output none | Out-Null
Assert-NativeCommandSucceeded 'Azure Storage access token acquisition'

$managementAccessToken = $null
$healthModelAnnotationMap = $null

if (-not $SkipHealthModelAnnotation) {
    $managementAccessToken = Get-ManagementAccessToken
    $healthModelAnnotationMap = Get-HealthModelAnnotationMap -Path $HealthModelAnnotationMapPath
}

foreach ($app in $apps) {
    Write-Host "Uploading $($app.ZipPath) to $($app.Container)\released-package.zip..."
    az storage blob upload `
        --account-name $StorageAccountName `
        --container-name $app.Container `
        --name released-package.zip `
        --file $app.ZipPath `
        --auth-mode login `
        --overwrite true `
        --content-type application/zip `
        --output none
    Assert-NativeCommandSucceeded "$($app.Name) package upload"

    Write-Host "Restarting $($app.Name)..."
    az functionapp restart --resource-group $ResourceGroupName --name $app.Name --output none
    Assert-NativeCommandSucceeded "$($app.Name) restart"

    Write-Host "Syncing triggers for $($app.Name)..."
    $appId = az functionapp show --resource-group $ResourceGroupName --name $app.Name --query id --output tsv
    Assert-NativeCommandSucceeded "$($app.Name) resource ID lookup"
    az rest --method post --url "https://management.azure.com$appId/syncfunctiontriggers?api-version=2023-12-01" --output none
    Assert-NativeCommandSucceeded "$($app.Name) trigger sync"

    if (-not $SkipHealthModelAnnotation) {
        $entityNames = Get-HealthModelAnnotationEntityNames -Map $healthModelAnnotationMap -AppName $app.Name -ResourceId $appId -Component $app.ArtifactName
        foreach ($entityName in $entityNames) {
            Write-Host "Adding deployment annotation to Health Model entity $entityName for $($app.Name)..."
            Add-HealthModelDeploymentAnnotation `
                -ModelRoot $healthModelAnnotationMap.healthModelResourceId `
                -EntityName $entityName `
                -DeploymentVersion $DeploymentVersion `
                -DeploymentRollout $DeploymentRollout `
                -Description $DeploymentAnnotationDescription `
                -AccessToken $managementAccessToken
        }
    }
}

foreach ($app in $apps) {
    Write-Host "Functions for $($app.Name):"
    az functionapp function list --resource-group $ResourceGroupName --name $app.Name --query "[].name" --output table
    Assert-NativeCommandSucceeded "$($app.Name) function list"
}
