@description('Azure region for Event Hubs.')
param location string

@description('Globally unique Event Hubs namespace name.')
param namespaceName string

@description('Event hub name for expense submissions.')
param eventHubName string

@description('Tags applied to all resources.')
param tags object

@description('When true, disables public network access.')
param restrictNetworkAccess bool = true

resource namespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    disableLocalAuth: true
    isAutoInflateEnabled: false
    kafkaEnabled: false
    minimumTlsVersion: '1.2'
    publicNetworkAccess: restrictNetworkAccess ? 'Disabled' : 'Enabled'
  }
}

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: namespace
  name: eventHubName
  properties: {
    messageRetentionInDays: 7
    partitionCount: 2
  }
}

resource workerConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = {
  parent: eventHub
  name: 'expense-worker'
  properties: {
  }
}

output id string = namespace.id
output namespaceName string = namespace.name
output fullyQualifiedNamespace string = '${namespace.name}.servicebus.windows.net'
output eventHubName string = eventHub.name
output consumerGroupName string = workerConsumerGroup.name
