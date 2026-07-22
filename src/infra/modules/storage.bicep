@description('Azure region for the storage account.')
param location string

@description('Globally unique storage account name.')
@minLength(3)
@maxLength(24)
param name string

@description('Name of the blob container that stores synthetic receipt payloads.')
param receiptContainerName string

@description('Name of the Storage Queue reserved for future demo signals/events.')
param storageQueueName string

@description('Name of the blob container used by the BFF Function App for Flex Consumption deployment packages.')
param bffPackageContainerName string

@description('Name of the blob container used by the worker Function App for Flex Consumption deployment packages.')
param workerPackageContainerName string

@description('Name of the blob container used by the OCR Function App for Flex Consumption deployment packages.')
param ocrPackageContainerName string

@description('Tags applied to all resources.')
param tags object

@description('When true, disables public network access except explicit deployment client IP ranges.')
param restrictNetworkAccess bool = true

@description('Optional public IPv4 ranges allowed through the storage firewall for developer deployment access. Leave empty to disable public network access.')
param deploymentClientIpRanges array = []

var deploymentIpRules = [
  for ipRange in deploymentClientIpRanges: {
    action: 'Allow'
    value: ipRange
  }
]

resource account 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: (!restrictNetworkAccess || !empty(deploymentClientIpRanges)) ? 'Enabled' : 'Disabled'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'None'
      defaultAction: restrictNetworkAccess ? 'Deny' : 'Allow'
      ipRules: restrictNetworkAccess ? deploymentIpRules : []
      virtualNetworkRules: []
    }
    encryption: {
      keySource: 'Microsoft.Storage'
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
        queue: {
          enabled: true
        }
        table: {
          enabled: true
        }
      }
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: account
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2023-05-01' = {
  parent: account
  name: 'default'
}

resource receiptContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: receiptContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource bffPackageContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: bffPackageContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource workerPackageContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: workerPackageContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource ocrPackageContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: ocrPackageContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource storageQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-05-01' = {
  parent: queueService
  name: storageQueueName
}

output id string = account.id
output name string = account.name
output receiptContainerName string = receiptContainer.name
output storageQueueName string = storageQueue.name
output bffPackageContainerUri string = '${account.properties.primaryEndpoints.blob}${bffPackageContainer.name}'
output workerPackageContainerUri string = '${account.properties.primaryEndpoints.blob}${workerPackageContainer.name}'
output ocrPackageContainerUri string = '${account.properties.primaryEndpoints.blob}${ocrPackageContainer.name}'
output blobEndpoint string = account.properties.primaryEndpoints.blob
output queueEndpoint string = account.properties.primaryEndpoints.queue
output tableEndpoint string = account.properties.primaryEndpoints.table
