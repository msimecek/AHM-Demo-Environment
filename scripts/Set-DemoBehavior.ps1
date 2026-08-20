param(
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,

    [ValidateRange(0, 1)]
    [double] $OcrFailureRate,

    [ValidateRange(0, 600000)]
    [int] $OcrResponseDelayMs,

    [bool] $ExternalOcrProviderHeartbeatEnabled,

    [string] $ExternalOcrProviderHeartbeatSchedule,

    [ValidateRange(0, 1)]
    [double] $ExternalOcrProviderReportProbability,

    [ValidateSet('Healthy', 'Degraded', 'Unhealthy', 'Unknown')]
    [string] $ExternalOcrProviderHealth,

    [ValidateRange(1, 10080)]
    [int] $ExternalOcrProviderReportExpiryMinutes,

    [ValidateRange(0, 600000)]
    [int] $WorkerProcessingDelayMs,

    [bool] $KeepAliveEnabled,

    [string] $KeepAliveSchedule,

    [ValidateRange(1, 100)]
    [int] $KeepAliveBatchSize
)

$ErrorActionPreference = 'Stop'

$behaviors = @(
    @{ Parameter = 'OcrFailureRate'; Component = 'ocr'; Setting = 'ExpenseFlow__OcrFailureRate' }
    @{ Parameter = 'OcrResponseDelayMs'; Component = 'ocr'; Setting = 'ExpenseFlow__OcrDelayMs' }
    @{ Parameter = 'ExternalOcrProviderHeartbeatEnabled'; Component = 'ocr'; Setting = 'ExpenseFlow__ExternalOcrProviderHeartbeatEnabled' }
    @{ Parameter = 'ExternalOcrProviderHeartbeatSchedule'; Component = 'ocr'; Setting = 'ExternalOcrProviderHeartbeatSchedule' }
    @{ Parameter = 'ExternalOcrProviderReportProbability'; Component = 'ocr'; Setting = 'ExpenseFlow__ExternalOcrProviderHeartbeatSendProbability' }
    @{ Parameter = 'ExternalOcrProviderHealth'; Component = 'ocr'; Setting = 'ExpenseFlow__ExternalOcrProviderHealth' }
    @{ Parameter = 'ExternalOcrProviderReportExpiryMinutes'; Component = 'ocr'; Setting = 'ExpenseFlow__ExternalOcrProviderHealthReportExpiresInMinutes' }
    @{ Parameter = 'WorkerProcessingDelayMs'; Component = 'worker'; Setting = 'ExpenseFlow__ProcessingDelayMs' }
    @{ Parameter = 'KeepAliveEnabled'; Component = 'bff'; Setting = 'ExpenseFlow__KeepAliveEnabled' }
    @{ Parameter = 'KeepAliveSchedule'; Component = 'bff'; Setting = 'KeepAliveSchedule' }
    @{ Parameter = 'KeepAliveBatchSize'; Component = 'bff'; Setting = 'ExpenseFlow__KeepAliveBatchSize' }
)

function Assert-NativeCommandSucceeded {
    param(
        [string] $Description
    )

    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

function Format-SettingValue {
    param(
        [object] $Value
    )

    if ($Value -is [bool]) {
        return $Value.ToString().ToLowerInvariant()
    }

    # Function App settings must use invariant decimal separators.
    if ($Value -is [double]) {
        return $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }

    return [string]$Value
}

function Get-FunctionAppName {
    param(
        [string] $ResourceGroupName,
        [string] $Component
    )

    $appName = az functionapp list --resource-group $ResourceGroupName --query "[?tags.component=='$Component'].name | [0]" --output tsv
    Assert-NativeCommandSucceeded "$Component Function App discovery"

    if ([string]::IsNullOrWhiteSpace($appName)) {
        throw "Could not find a Function App tagged 'component=$Component' in resource group '$ResourceGroupName'."
    }

    return $appName
}

$settingsByComponent = [ordered]@{}

foreach ($behavior in $behaviors) {
    if (-not $PSBoundParameters.ContainsKey($behavior.Parameter)) {
        continue
    }

    $value = Format-SettingValue -Value $PSBoundParameters[$behavior.Parameter]

    if (-not $settingsByComponent.Contains($behavior.Component)) {
        $settingsByComponent[$behavior.Component] = @()
    }

    $settingsByComponent[$behavior.Component] += "$($behavior.Setting)=$value"
}

if ($settingsByComponent.Count -eq 0) {
    throw 'Specify at least one behavior parameter.'
}

foreach ($component in @($settingsByComponent.Keys)) {
    $appName = Get-FunctionAppName -ResourceGroupName $ResourceGroupName -Component $component
    $settings = @($settingsByComponent[$component])

    Write-Host "Updating $appName ($component)..."
    az functionapp config appsettings set --resource-group $ResourceGroupName --name $appName --settings @settings --output none
    Assert-NativeCommandSucceeded "$appName app settings update"

    az functionapp restart --resource-group $ResourceGroupName --name $appName --output none
    Assert-NativeCommandSucceeded "$appName restart"

    foreach ($setting in $settings) {
        Write-Host "  $setting"
    }
}

Write-Host 'Runtime behavior updated. Restarted Function Apps reload settings within a few seconds.'
