#requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,
    [string] $BffFunctionAppName,
    [string] $WorkerFunctionAppName,
    [string] $OcrFunctionAppName,
    [string] $Configuration = 'Release',
    [string] $ArtifactsPath = (Join-Path $env:TEMP 'expenseflow-function-packages'),
    [string] $HealthModelDetailsMapPath = (Join-Path $PSScriptRoot '..\.deployment\health-model-details.json'),
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

function Assert-ScmEndpointAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string] $AppName,

        [Parameter(Mandatory = $true)]
        [string] $AccessToken
    )

    $appId = az functionapp show --resource-group $ResourceGroupName --name $AppName --query id --output tsv
    Assert-NativeCommandSucceeded "$AppName resource ID lookup"
    $appId = Get-RequiredValue $appId "$AppName resource ID"

    $hostNamesJson = az rest --method get --url "https://management.azure.com${appId}?api-version=2024-04-01" --query 'properties.enabledHostNames' --output json
    Assert-NativeCommandSucceeded "$AppName hostname lookup"
    $scmHostNames = @($hostNamesJson | ConvertFrom-Json | Where-Object { $_ -match '\.scm\.' })
    if ($scmHostNames.Count -ne 1) {
        throw "Expected one SCM hostname for '$AppName', but found $($scmHostNames.Count)."
    }

    $uri = "https://$($scmHostNames[0])/api/deployments"
    Write-Host "Checking SCM endpoint for $AppName..."
    $response = Invoke-WebRequest -Uri $uri -Method Get -Headers @{ Authorization = "Bearer $AccessToken" } -SkipHttpErrorCheck -MaximumRedirection 0 -TimeoutSec 30
    if ($response.StatusCode -ne 200) {
        throw "SCM endpoint '$uri' returned HTTP $($response.StatusCode). Check deployment permissions, SCM access restrictions, public network access, or private endpoint connectivity and DNS."
    }

    Write-Host "SCM endpoint is reachable for $AppName."
    return $appId
}

function Assert-FunctionPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string[]] $ExpectedFunctions
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Package not found: $Path"
    }

    $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        if ($null -eq $archive.GetEntry('host.json')) {
            throw "Package '$Path' must contain host.json at the ZIP root."
        }

        $metadataEntry = $archive.GetEntry('functions.metadata')
        if ($null -eq $metadataEntry) {
            throw "Package '$Path' must contain functions.metadata at the ZIP root. Build the .NET Function App before deployment."
        }

        $reader = [System.IO.StreamReader]::new($metadataEntry.Open())
        try {
            $metadata = $reader.ReadToEnd() | ConvertFrom-Json
        }
        finally {
            $reader.Dispose()
        }

        $missingFunctions = @($ExpectedFunctions | Where-Object { $_ -notin @($metadata.name) })
        if ($missingFunctions.Count -gt 0) {
            throw "Package '$Path' is missing expected functions: $($missingFunctions -join ', ')."
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Assert-FunctionDeployment {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string] $AppName,

        [Parameter(Mandatory = $true)]
        [string] $AppId,

        [Parameter(Mandatory = $true)]
        [string[]] $ExpectedFunctions
    )

    $maximumAttempts = 6
    foreach ($attempt in 1..$maximumAttempts) {
        $state = az rest --method get --url "https://management.azure.com${AppId}?api-version=2024-04-01" --query 'properties.state' --output tsv
        Assert-NativeCommandSucceeded "$AppName state lookup"
        $state = Get-RequiredValue $state "$AppName state"
        $functionsJson = az functionapp function list --resource-group $ResourceGroupName --name $AppName --output json
        Assert-NativeCommandSucceeded "$AppName function list"
        $functions = @($functionsJson | ConvertFrom-Json)
        $enabledFunctionNames = @($functions | Where-Object { $_.isDisabled -eq $false } | ForEach-Object { ($_.name -split '/')[-1] })
        $missingFunctions = @($ExpectedFunctions | Where-Object { $_ -notin $enabledFunctionNames })

        if ($state -eq 'Running' -and $missingFunctions.Count -eq 0) {
            Write-Host "Deployment verified for ${AppName}: Running; enabled functions: $($ExpectedFunctions -join ', ')."
            return
        }

        if ($attempt -lt $maximumAttempts) {
            Write-Host "Waiting for $AppName to be ready (attempt $attempt of $maximumAttempts): state '$state'; missing or disabled functions: $($missingFunctions -join ', ')."
            Start-Sleep -Seconds 10
        }
    }

    throw "Deployment validation failed for '$AppName': state '$state'; missing or disabled functions: $($missingFunctions -join ', ')."
}

function Get-ManagementAccessToken {
    $accessToken = az account get-access-token --resource https://management.azure.com/ --query accessToken --output tsv
    Assert-NativeCommandSucceeded 'Azure management access token acquisition'
    return Get-RequiredValue $accessToken 'Azure management access token'
}

function Get-HealthModelDetailsMap {
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
    $url = "https://management.azure.com$ModelRoot/entities/$escapedEntityName/addDataAnnotation?api-version=2026-09-01-preview"
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
$healthModelDetailsMap = $null

if (-not $SkipHealthModelAnnotation) {
    $healthModelDetailsMap = Get-HealthModelDetailsMap -Path $HealthModelDetailsMapPath
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

$BffFunctionAppName = Get-RequiredValue $BffFunctionAppName 'BFF Function App name'
$WorkerFunctionAppName = Get-RequiredValue $WorkerFunctionAppName 'Worker Function App name'
$OcrFunctionAppName = Get-RequiredValue $OcrFunctionAppName 'OCR Function App name'

$apps = @(
    @{
        Name = $BffFunctionAppName
        Project = Join-Path $repositoryRoot 'src\app\ExpenseFlow.Bff\ExpenseFlow.Bff.csproj'
        ExpectedFunctions = @('SubmitSyntheticExpense', 'KeepAlive')
        ArtifactName = 'bff'
    },
    @{
        Name = $WorkerFunctionAppName
        Project = Join-Path $repositoryRoot 'src\app\ExpenseFlow.Worker\ExpenseFlow.Worker.csproj'
        ExpectedFunctions = @('ProcessExpense')
        ArtifactName = 'worker'
    },
    @{
        Name = $OcrFunctionAppName
        Project = Join-Path $repositoryRoot 'src\app\ExpenseFlow.Ocr\ExpenseFlow.Ocr.csproj'
        ExpectedFunctions = @('ExtractReceipt', 'ExternalOcrProviderHeartbeat')
        ArtifactName = 'ocr'
    }
)

$managementAccessToken = Get-ManagementAccessToken

foreach ($app in $apps) {
    $app.Id = Assert-ScmEndpointAvailable -ResourceGroupName $ResourceGroupName -AppName $app.Name -AccessToken $managementAccessToken
    if (-not $SkipHealthModelAnnotation) {
        $app.EntityNames = @(Get-HealthModelAnnotationEntityNames -Map $healthModelDetailsMap -AppName $app.Name -ResourceId $app.Id -Component $app.ArtifactName)
    }
}

New-Item -ItemType Directory -Force $ArtifactsPath | Out-Null
$ArtifactsPath = (Resolve-Path -LiteralPath $ArtifactsPath).Path

if (-not $SkipBuild) {
    foreach ($app in $apps) {
        $publishPath = Join-Path $ArtifactsPath $app.ArtifactName
        $zipPath = Join-Path $ArtifactsPath "$($app.ArtifactName).zip"

        if (Test-Path -LiteralPath $publishPath) {
            Remove-Item -LiteralPath $publishPath -Recurse -Force
        }
        dotnet publish $app.Project --configuration $Configuration --output $publishPath --nologo --verbosity minimal
        Assert-NativeCommandSucceeded "$($app.ArtifactName) publish"
        Compress-Archive -Path "$publishPath\*" -DestinationPath $zipPath -Force
        $app.ZipPath = $zipPath
    }
}
else {
    foreach ($app in $apps) {
        $zipPath = Join-Path $ArtifactsPath "$($app.ArtifactName).zip"
        $app.ZipPath = $zipPath
    }
}

foreach ($app in $apps) {
    Assert-FunctionPackage -Path $app.ZipPath -ExpectedFunctions $app.ExpectedFunctions
}

foreach ($app in $apps) {
    Write-Host "Deploying $($app.ZipPath) to $($app.Name) through SCM..."
    az functionapp deployment source config-zip `
        --resource-group $ResourceGroupName `
        --name $app.Name `
        --src $app.ZipPath `
        --build-remote false `
        --output none
    Assert-NativeCommandSucceeded "$($app.Name) package deployment"
    Assert-FunctionDeployment -ResourceGroupName $ResourceGroupName -AppName $app.Name -AppId $app.Id -ExpectedFunctions $app.ExpectedFunctions

    if (-not $SkipHealthModelAnnotation) {
        foreach ($entityName in $app.EntityNames) {
            Write-Host "Adding deployment annotation to Health Model entity $entityName for $($app.Name)..."
            Add-HealthModelDeploymentAnnotation `
                -ModelRoot $healthModelDetailsMap.healthModelResourceId `
                -EntityName $entityName `
                -DeploymentVersion $DeploymentVersion `
                -DeploymentRollout $DeploymentRollout `
                -Description $DeploymentAnnotationDescription `
                -AccessToken $managementAccessToken
        }
    }
}

Write-Host "Function App deployment complete. Resource group: $ResourceGroupName"
