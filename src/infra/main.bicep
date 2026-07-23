targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Short workload name used in resource names.')
@minLength(3)
@maxLength(18)
param workloadName string = 'expenseflow'

@description('Deployment environment suffix.')
@allowed([
  'dev'
  'test'
  'demo'
])
param environmentName string = 'demo'

@description('Tags applied to all resources.')
param tags object = {}

@description('Optional public IPv4 ranges allowed through the storage firewall for developer deployment access. Leave empty to disable public network access.')
param deploymentClientIpRanges array = []

@description('When true, applies the private-only network baseline. Set false temporarily for deployment/debugging.')
param restrictNetworkAccess bool = true

@description('When true, writes the current OCR Function host key to Key Vault.')
param updateOcrFunctionKeySecret bool = true

@description('When true, allows public Azure Monitor query access for demo health-model queries while keeping ingestion private.')
param allowPublicMonitorQueryAccess bool = false

var baseName = toLower('${workloadName}-${environmentName}')
var compactName = replace(baseName, '-', '')
var uniqueSuffix = uniqueString(resourceGroup().id, baseName)
var commonTags = union(tags, {
  workload: workloadName
  environment: environmentName
})

var storageName = take('${take(compactName, 9)}st${uniqueSuffix}', 24)
var secondaryStorageName = take('${take(compactName, 8)}st2${uniqueSuffix}', 24)
var serviceBusNamespaceName = take('sb-${baseName}-${uniqueSuffix}', 50)
var cosmosAccountName = take('cosmos-${baseName}-${uniqueSuffix}', 44)
var keyVaultName = take('${take(compactName, 10)}kv${uniqueSuffix}', 24)
var logAnalyticsWorkspaceName = take('law-${baseName}-${uniqueSuffix}', 63)
var applicationInsightsName = take('appi-${baseName}-${uniqueSuffix}', 255)
var azureMonitorPrivateLinkScopeName = take('ampls-${baseName}-${uniqueSuffix}', 260)
var bffFunctionPlanName = take('asp-${baseName}-bff-${uniqueSuffix}', 40)
var workerFunctionPlanName = take('asp-${baseName}-worker-${uniqueSuffix}', 40)
var ocrFunctionPlanName = take('asp-${baseName}-ocr-${uniqueSuffix}', 40)
var bffFunctionAppName = take('func-${baseName}-bff-${uniqueSuffix}', 60)
var workerFunctionAppName = take('func-${baseName}-worker-${uniqueSuffix}', 60)
var ocrFunctionAppName = take('func-${baseName}-ocr-${uniqueSuffix}', 60)
var ocrFunctionKeySecretName = 'ocr-function-key'
var healthModelName = take('hm-${baseName}-${uniqueSuffix}', 90)

var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var storageQueueDataContributorRoleId = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
var storageTableDataContributorRoleId = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
var serviceBusDataSenderRoleId = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
var serviceBusDataReceiverRoleId = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'
var cosmosSqlDataContributorRoleId = '00000000-0000-0000-0000-000000000002'
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'
var monitoringReaderRoleId = '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
var logAnalyticsReaderRoleId = '73c42c96-874c-492b-b04d-ab87d138a893'

var functionHostStorageSettings = [
  {
    name: 'AzureWebJobsStorage__blobServiceUri'
    value: storage.outputs.blobEndpoint
  }
  {
    name: 'AzureWebJobsStorage__queueServiceUri'
    value: storage.outputs.queueEndpoint
  }
  {
    name: 'AzureWebJobsStorage__tableServiceUri'
    value: storage.outputs.tableEndpoint
  }
  {
    name: 'AzureWebJobsStorage__credential'
    value: 'managedidentity'
  }
]

var receiptStorageSettings = [
  {
    name: 'ExpenseFlow__ReceiptContainerName'
    value: storage.outputs.receiptContainerName
  }
  {
    name: 'ExpenseFlow__StorageBlobServiceUri'
    value: storage.outputs.blobEndpoint
  }
]

var storageQueueSettings = [
  {
    name: 'ExpenseFlow__StorageQueueName'
    value: storage.outputs.storageQueueName
  }
  {
    name: 'ExpenseFlow__StorageQueueServiceUri'
    value: storage.outputs.queueEndpoint
  }
]

var queueBindingSettings = [
  {
    name: 'ExpensesQueueName'
    value: serviceBus.outputs.queueName
  }
  {
    name: 'ServiceBusConnection__fullyQualifiedNamespace'
    value: serviceBus.outputs.fullyQualifiedNamespace
  }
]

var cosmosSettings = [
  {
    name: 'ExpenseFlow__CosmosEndpoint'
    value: cosmos.outputs.endpoint
  }
  {
    name: 'ExpenseFlow__CosmosDatabaseName'
    value: cosmos.outputs.databaseName
  }
  {
    name: 'ExpenseFlow__CosmosContainerName'
    value: cosmos.outputs.containerName
  }
]

var applicationInsightsSettings = [
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: observability.outputs.applicationInsightsConnectionString
  }
  {
    name: 'APPLICATIONINSIGHTS_AUTHENTICATION_STRING'
    value: 'Authorization=AAD'
  }
]

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
    baseName: baseName
    tags: commonTags
    addressPrefix: '10.42.0.0/16'
    functionSubnetPrefix: '10.42.1.0/24'
    privateEndpointSubnetPrefix: '10.42.2.0/24'
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    location: location
    name: storageName
    tags: commonTags
    receiptContainerName: 'receipts'
    storageQueueName: 'expense-events'
    bffPackageContainerName: 'function-packages-bff'
    workerPackageContainerName: 'function-packages-worker'
    ocrPackageContainerName: 'function-packages-ocr'
    restrictNetworkAccess: restrictNetworkAccess
    deploymentClientIpRanges: deploymentClientIpRanges
  }
}

module secondaryStorage 'modules/storage.bicep' = {
  name: 'secondary-storage'
  params: {
    location: location
    name: secondaryStorageName
    tags: commonTags
    receiptContainerName: 'receipts'
    storageQueueName: 'expense-events'
    bffPackageContainerName: 'function-packages-bff'
    workerPackageContainerName: 'function-packages-worker'
    ocrPackageContainerName: 'function-packages-ocr'
    restrictNetworkAccess: restrictNetworkAccess
    deploymentClientIpRanges: deploymentClientIpRanges
  }
}

module serviceBus 'modules/service-bus.bicep' = {
  name: 'service-bus'
  params: {
    location: location
    namespaceName: serviceBusNamespaceName
    queueName: 'expenses'
    tags: commonTags
    restrictNetworkAccess: restrictNetworkAccess
  }
}

module cosmos 'modules/cosmos-db.bicep' = {
  name: 'cosmos-db'
  params: {
    location: location
    accountName: cosmosAccountName
    databaseName: 'expenseflow'
    containerName: 'expenses'
    tags: commonTags
    restrictNetworkAccess: restrictNetworkAccess
  }
}

module keyVault 'modules/key-vault.bicep' = {
  name: 'key-vault'
  params: {
    location: location
    name: keyVaultName
    tags: commonTags
    restrictNetworkAccess: restrictNetworkAccess
  }
}

module observability 'modules/observability.bicep' = {
  name: 'observability'
  params: {
    location: location
    workspaceName: logAnalyticsWorkspaceName
    applicationInsightsName: applicationInsightsName
    privateLinkScopeName: azureMonitorPrivateLinkScopeName
    tags: commonTags
    restrictNetworkAccess: restrictNetworkAccess
    allowPublicMonitorQueryAccess: allowPublicMonitorQueryAccess
  }
}

resource bffFunctionPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: bffFunctionPlanName
  location: location
  tags: union(commonTags, {
    component: 'bff'
  })
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

resource workerFunctionPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: workerFunctionPlanName
  location: location
  tags: union(commonTags, {
    component: 'worker'
  })
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

resource ocrFunctionPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: ocrFunctionPlanName
  location: location
  tags: union(commonTags, {
    component: 'ocr'
  })
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

module bffFunction 'modules/function-app.bicep' = {
  name: 'bff-function'
  params: {
    location: location
    appName: bffFunctionAppName
    planId: bffFunctionPlan.id
    subnetId: network.outputs.functionSubnetId
    packageContainerUri: storage.outputs.bffPackageContainerUri
    deploymentClientIpRanges: deploymentClientIpRanges
    restrictNetworkAccess: restrictNetworkAccess
    tags: union(commonTags, {
      component: 'bff'
    })
    appSettings: concat(functionHostStorageSettings, applicationInsightsSettings, receiptStorageSettings, storageQueueSettings, queueBindingSettings, [
      {
        name: 'ExpenseFlow__KeepAliveEnabled'
        value: 'true'
      }
      {
        name: 'KeepAliveSchedule'
        value: '*/30 * * * * *'
      }
      {
        name: 'ExpenseFlow__KeepAliveBatchSize'
        value: '1'
      }
    ])
  }
}

module workerFunction 'modules/function-app.bicep' = {
  name: 'worker-function'
  params: {
    location: location
    appName: workerFunctionAppName
    planId: workerFunctionPlan.id
    subnetId: network.outputs.functionSubnetId
    packageContainerUri: storage.outputs.workerPackageContainerUri
    deploymentClientIpRanges: deploymentClientIpRanges
    restrictNetworkAccess: restrictNetworkAccess
    tags: union(commonTags, {
      component: 'worker'
    })
    appSettings: concat(functionHostStorageSettings, applicationInsightsSettings, receiptStorageSettings, storageQueueSettings, queueBindingSettings, cosmosSettings, [
      {
        name: 'ExpenseFlow__OcrServiceBaseUrl'
        value: 'https://${ocrFunction.outputs.defaultHostName}'
      }
      {
        name: 'ExpenseFlow__OcrFunctionKey'
        value: '@Microsoft.KeyVault(VaultName=${keyVault.outputs.name};SecretName=${ocrFunctionKeySecretName})'
      }
      {
        name: 'ExpenseFlow__ProcessingDelayMs'
        value: '1000'
      }
    ])
  }
}

module ocrFunction 'modules/function-app.bicep' = {
  name: 'ocr-function'
  dependsOn: [
    bffFunction
  ]
  params: {
    location: location
    appName: ocrFunctionAppName
    planId: ocrFunctionPlan.id
    subnetId: network.outputs.functionSubnetId
    packageContainerUri: storage.outputs.ocrPackageContainerUri
    deploymentClientIpRanges: deploymentClientIpRanges
    restrictNetworkAccess: restrictNetworkAccess
    tags: union(commonTags, {
      component: 'ocr'
    })
    appSettings: concat(functionHostStorageSettings, applicationInsightsSettings, receiptStorageSettings, storageQueueSettings, [
      {
        name: 'ExpenseFlow__OcrDelayMs'
        value: '500'
      }
      {
        name: 'ExpenseFlow__OcrFailureRate'
        value: '0'
      }
    ])
  }
}

module storageBlobPrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'pe-storage-blob'
  params: {
    location: location
    name: take('pe-${storage.outputs.name}-blob', 80)
    subnetId: network.outputs.privateEndpointSubnetId
    targetResourceId: storage.outputs.id
    groupIds: [
      'blob'
    ]
    privateDnsZoneId: network.outputs.storageBlobPrivateDnsZoneId
    tags: commonTags
  }
}

module storageQueuePrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'pe-storage-queue'
  params: {
    location: location
    name: take('pe-${storage.outputs.name}-queue', 80)
    subnetId: network.outputs.privateEndpointSubnetId
    targetResourceId: storage.outputs.id
    groupIds: [
      'queue'
    ]
    privateDnsZoneId: network.outputs.storageQueuePrivateDnsZoneId
    tags: commonTags
  }
}

module storageTablePrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'pe-storage-table'
  params: {
    location: location
    name: take('pe-${storage.outputs.name}-table', 80)
    subnetId: network.outputs.privateEndpointSubnetId
    targetResourceId: storage.outputs.id
    groupIds: [
      'table'
    ]
    privateDnsZoneId: network.outputs.storageTablePrivateDnsZoneId
    tags: commonTags
  }
}

module storageFilePrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'pe-storage-file'
  params: {
    location: location
    name: take('pe-${storage.outputs.name}-file', 80)
    subnetId: network.outputs.privateEndpointSubnetId
    targetResourceId: storage.outputs.id
    groupIds: [
      'file'
    ]
    privateDnsZoneId: network.outputs.storageFilePrivateDnsZoneId
    tags: commonTags
  }
}

module secondaryStorageBlobPrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'pe-secondary-storage-blob'
  params: {
    location: location
    name: take('pe-${secondaryStorage.outputs.name}-blob', 80)
    subnetId: network.outputs.privateEndpointSubnetId
    targetResourceId: secondaryStorage.outputs.id
    groupIds: [
      'blob'
    ]
    privateDnsZoneId: network.outputs.storageBlobPrivateDnsZoneId
    tags: commonTags
  }
}

module secondaryStorageQueuePrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'pe-secondary-storage-queue'
  params: {
    location: location
    name: take('pe-${secondaryStorage.outputs.name}-queue', 80)
    subnetId: network.outputs.privateEndpointSubnetId
    targetResourceId: secondaryStorage.outputs.id
    groupIds: [
      'queue'
    ]
    privateDnsZoneId: network.outputs.storageQueuePrivateDnsZoneId
    tags: commonTags
  }
}

module secondaryStorageTablePrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'pe-secondary-storage-table'
  params: {
    location: location
    name: take('pe-${secondaryStorage.outputs.name}-table', 80)
    subnetId: network.outputs.privateEndpointSubnetId
    targetResourceId: secondaryStorage.outputs.id
    groupIds: [
      'table'
    ]
    privateDnsZoneId: network.outputs.storageTablePrivateDnsZoneId
    tags: commonTags
  }
}

module secondaryStorageFilePrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'pe-secondary-storage-file'
  params: {
    location: location
    name: take('pe-${secondaryStorage.outputs.name}-file', 80)
    subnetId: network.outputs.privateEndpointSubnetId
    targetResourceId: secondaryStorage.outputs.id
    groupIds: [
      'file'
    ]
    privateDnsZoneId: network.outputs.storageFilePrivateDnsZoneId
    tags: commonTags
  }
}

module serviceBusPrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'pe-service-bus'
  params: {
    location: location
    name: take('pe-${serviceBus.outputs.namespaceName}', 80)
    subnetId: network.outputs.privateEndpointSubnetId
    targetResourceId: serviceBus.outputs.id
    groupIds: [
      'namespace'
    ]
    privateDnsZoneId: network.outputs.serviceBusPrivateDnsZoneId
    tags: commonTags
  }
}

module cosmosPrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'pe-cosmos-db'
  params: {
    location: location
    name: take('pe-${cosmos.outputs.name}', 80)
    subnetId: network.outputs.privateEndpointSubnetId
    targetResourceId: cosmos.outputs.id
    groupIds: [
      'Sql'
    ]
    privateDnsZoneId: network.outputs.cosmosPrivateDnsZoneId
    tags: commonTags
  }
}

module bffPrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'pe-bff-function'
  params: {
    location: location
    name: take('pe-${bffFunction.outputs.name}', 80)
    subnetId: network.outputs.privateEndpointSubnetId
    targetResourceId: bffFunction.outputs.id
    groupIds: [
      'sites'
    ]
    privateDnsZoneId: network.outputs.webAppPrivateDnsZoneId
    tags: commonTags
  }
}

module workerPrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'pe-worker-function'
  params: {
    location: location
    name: take('pe-${workerFunction.outputs.name}', 80)
    subnetId: network.outputs.privateEndpointSubnetId
    targetResourceId: workerFunction.outputs.id
    groupIds: [
      'sites'
    ]
    privateDnsZoneId: network.outputs.webAppPrivateDnsZoneId
    tags: commonTags
  }
}

module ocrPrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'pe-ocr-function'
  params: {
    location: location
    name: take('pe-${ocrFunction.outputs.name}', 80)
    subnetId: network.outputs.privateEndpointSubnetId
    targetResourceId: ocrFunction.outputs.id
    groupIds: [
      'sites'
    ]
    privateDnsZoneId: network.outputs.webAppPrivateDnsZoneId
    tags: commonTags
  }
}

module keyVaultPrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'pe-key-vault'
  params: {
    location: location
    name: take('pe-${keyVault.outputs.name}', 80)
    subnetId: network.outputs.privateEndpointSubnetId
    targetResourceId: keyVault.outputs.id
    groupIds: [
      'vault'
    ]
    privateDnsZoneId: network.outputs.keyVaultPrivateDnsZoneId
    tags: commonTags
  }
}

module azureMonitorPrivateEndpoint 'modules/monitor-private-endpoint.bicep' = {
  name: 'pe-azure-monitor'
  params: {
    location: location
    name: take('pe-${azureMonitorPrivateLinkScopeName}', 80)
    subnetId: network.outputs.privateEndpointSubnetId
    privateLinkScopeId: observability.outputs.privateLinkScopeId
    privateDnsZoneIds: network.outputs.azureMonitorPrivateDnsZoneIds
    tags: commonTags
  }
}

module healthModel 'modules/health-model.bicep' = {
  name: 'health-model'
  params: {
    location: location
    healthModelName: healthModelName
    tags: commonTags
    storageAccountResourceId: storage.outputs.id
    secondaryStorageAccountResourceId: secondaryStorage.outputs.id
    workerFunctionResourceId: workerFunction.outputs.id
    logAnalyticsWorkspaceResourceId: observability.outputs.workspaceId
    bffPlanResourceId: bffFunctionPlan.id
    ocrFunctionResourceId: ocrFunction.outputs.id
    bffFunctionResourceId: bffFunction.outputs.id
    ocrPlanResourceId: ocrFunctionPlan.id
    workerPlanResourceId: workerFunctionPlan.id
    keyVaultResourceId: keyVault.outputs.id
    serviceBusNamespaceResourceId: serviceBus.outputs.id
    cosmosAccountResourceId: cosmos.outputs.id
    bffAppRoleName: bffFunction.outputs.name
    workerAppRoleName: workerFunction.outputs.name
    ocrAppRoleName: ocrFunction.outputs.name
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageName
}

resource secondaryStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: secondaryStorageName
}

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' existing = {
  name: serviceBusNamespaceName
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' existing = {
  name: cosmosAccountName
}

resource keyVaultResource 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource applicationInsightsResource 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource logAnalyticsWorkspaceResource 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource ocrFunctionKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (updateOcrFunctionKeySecret) {
  name: ocrFunctionKeySecretName
  parent: keyVaultResource
  properties: {
    contentType: 'Azure Functions host key'
    value: listKeys('${resourceId('Microsoft.Web/sites', ocrFunctionAppName)}/host/default', '2023-12-01').functionKeys.default
  }
  dependsOn: [
    keyVault
    ocrFunction
    keyVaultPrivateEndpoint
  ]
}

resource bffBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, bffFunctionAppName, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: bffFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource bffQueueRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, bffFunctionAppName, storageQueueDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRoleId)
    principalId: bffFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource bffTableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, bffFunctionAppName, storageTableDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: bffFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource workerBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, workerFunctionAppName, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: workerFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource workerQueueRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, workerFunctionAppName, storageQueueDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRoleId)
    principalId: workerFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource workerTableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, workerFunctionAppName, storageTableDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: workerFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource ocrBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, ocrFunctionAppName, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: ocrFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource ocrQueueRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, ocrFunctionAppName, storageQueueDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRoleId)
    principalId: ocrFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource ocrTableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, ocrFunctionAppName, storageTableDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: ocrFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource bffSecondaryBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(secondaryStorageAccount.id, bffFunctionAppName, storageBlobDataContributorRoleId)
  scope: secondaryStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: bffFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    secondaryStorage
  ]
}

resource bffSecondaryQueueRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(secondaryStorageAccount.id, bffFunctionAppName, storageQueueDataContributorRoleId)
  scope: secondaryStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRoleId)
    principalId: bffFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    secondaryStorage
  ]
}

resource bffSecondaryTableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(secondaryStorageAccount.id, bffFunctionAppName, storageTableDataContributorRoleId)
  scope: secondaryStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: bffFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    secondaryStorage
  ]
}

resource workerSecondaryBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(secondaryStorageAccount.id, workerFunctionAppName, storageBlobDataContributorRoleId)
  scope: secondaryStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: workerFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    secondaryStorage
  ]
}

resource workerSecondaryQueueRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(secondaryStorageAccount.id, workerFunctionAppName, storageQueueDataContributorRoleId)
  scope: secondaryStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRoleId)
    principalId: workerFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    secondaryStorage
  ]
}

resource workerSecondaryTableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(secondaryStorageAccount.id, workerFunctionAppName, storageTableDataContributorRoleId)
  scope: secondaryStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: workerFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    secondaryStorage
  ]
}

resource ocrSecondaryBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(secondaryStorageAccount.id, ocrFunctionAppName, storageBlobDataContributorRoleId)
  scope: secondaryStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: ocrFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    secondaryStorage
  ]
}

resource ocrSecondaryQueueRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(secondaryStorageAccount.id, ocrFunctionAppName, storageQueueDataContributorRoleId)
  scope: secondaryStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRoleId)
    principalId: ocrFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    secondaryStorage
  ]
}

resource ocrSecondaryTableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(secondaryStorageAccount.id, ocrFunctionAppName, storageTableDataContributorRoleId)
  scope: secondaryStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: ocrFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    secondaryStorage
  ]
}

resource bffServiceBusSenderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, bffFunctionAppName, serviceBusDataSenderRoleId)
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataSenderRoleId)
    principalId: bffFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource workerServiceBusReceiverRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, workerFunctionAppName, serviceBusDataReceiverRoleId)
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataReceiverRoleId)
    principalId: workerFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource workerKeyVaultSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVaultResource.id, workerFunctionAppName, keyVaultSecretsUserRoleId)
  scope: keyVaultResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: workerFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource bffApplicationInsightsPublisherRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(applicationInsightsResource.id, bffFunctionAppName, monitoringMetricsPublisherRoleId)
  scope: applicationInsightsResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
    principalId: bffFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource workerApplicationInsightsPublisherRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(applicationInsightsResource.id, workerFunctionAppName, monitoringMetricsPublisherRoleId)
  scope: applicationInsightsResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
    principalId: workerFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource ocrApplicationInsightsPublisherRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(applicationInsightsResource.id, ocrFunctionAppName, monitoringMetricsPublisherRoleId)
  scope: applicationInsightsResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
    principalId: ocrFunction.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource healthModelMonitoringReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, healthModelName, monitoringReaderRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringReaderRoleId)
    principalId: healthModel.outputs.healthModelPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource healthModelLogAnalyticsReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logAnalyticsWorkspaceResource.id, healthModelName, logAnalyticsReaderRoleId)
  scope: logAnalyticsWorkspaceResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', logAnalyticsReaderRoleId)
    principalId: healthModel.outputs.healthModelPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource bffCosmosRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  name: guid(cosmosAccount.id, bffFunctionAppName, cosmosSqlDataContributorRoleId)
  parent: cosmosAccount
  properties: {
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/${cosmosSqlDataContributorRoleId}'
    principalId: bffFunction.outputs.principalId
    scope: cosmosAccount.id
  }
}

resource workerCosmosRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  name: guid(cosmosAccount.id, workerFunctionAppName, cosmosSqlDataContributorRoleId)
  parent: cosmosAccount
  properties: {
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/${cosmosSqlDataContributorRoleId}'
    principalId: workerFunction.outputs.principalId
    scope: cosmosAccount.id
  }
}

output bffFunctionHostName string = bffFunction.outputs.defaultHostName
output workerFunctionHostName string = workerFunction.outputs.defaultHostName
output ocrFunctionHostName string = ocrFunction.outputs.defaultHostName
output serviceBusNamespace string = serviceBus.outputs.fullyQualifiedNamespace
output storageAccountName string = storage.outputs.name
output cosmosEndpoint string = cosmos.outputs.endpoint
output logAnalyticsWorkspaceName string = observability.outputs.workspaceName
output applicationInsightsName string = observability.outputs.applicationInsightsName
output healthModelResourceId string = healthModel.outputs.healthModelResourceId
output healthModelAnnotationMap object = {
  apiVersion: '2026-05-01-preview'
  subscriptionId: subscription().subscriptionId
  resourceGroupName: resourceGroup().name
  healthModelResourceId: healthModel.outputs.healthModelResourceId
  functionApps: [
    {
      name: bffFunction.outputs.name
      component: 'bff'
      resourceId: bffFunction.outputs.id
      entityNames: healthModel.outputs.bffDeploymentAnnotationEntityNames
    }
    {
      name: workerFunction.outputs.name
      component: 'worker'
      resourceId: workerFunction.outputs.id
      entityNames: healthModel.outputs.workerDeploymentAnnotationEntityNames
    }
    {
      name: ocrFunction.outputs.name
      component: 'ocr'
      resourceId: ocrFunction.outputs.id
      entityNames: healthModel.outputs.ocrDeploymentAnnotationEntityNames
    }
  ]
}
