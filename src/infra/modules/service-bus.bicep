@description('Azure region for Service Bus.')
param location string

@description('Globally unique Service Bus namespace name.')
param namespaceName string

@description('Queue name for expense processing jobs.')
param queueName string

@description('Tags applied to all resources.')
param tags object

@description('When true, disables public network access.')
param restrictNetworkAccess bool = true

resource namespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: 'Premium'
    tier: 'Premium'
    capacity: 1
  }
  properties: {
    disableLocalAuth: true
    minimumTlsVersion: '1.2'
    publicNetworkAccess: restrictNetworkAccess ? 'Disabled' : 'Enabled'
  }
}

resource queue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: namespace
  name: queueName
  properties: {
    deadLetteringOnMessageExpiration: true
    defaultMessageTimeToLive: 'P14D'
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    enableBatchedOperations: true
    enablePartitioning: false
    lockDuration: 'PT1M'
    maxDeliveryCount: 5
    requiresDuplicateDetection: false
    requiresSession: false
  }
}

output id string = namespace.id
output namespaceName string = namespace.name
output fullyQualifiedNamespace string = '${namespace.name}.servicebus.windows.net'
output queueName string = queue.name
