@description('Azure region for the Function App.')
param location string

@description('Function App name.')
param appName string

@description('App Service plan resource ID.')
param planId string

@description('Delegated subnet ID used for regional VNET integration.')
param subnetId string

@description('Blob container URI used by Flex Consumption for deployment packages.')
param packageContainerUri string

@description('Additional Function App settings.')
param appSettings array = []

@description('Optional public IPv4 ranges allowed to reach the Function App and SCM deployment endpoint. Leave empty to disable public network access.')
param deploymentClientIpRanges array = []

@description('Tags applied to the Function App.')
param tags object

@description('When true, disables public network access except explicit deployment client IP ranges.')
param restrictNetworkAccess bool = true

var deploymentAccessRules = [
  for (ipRange, index) in deploymentClientIpRanges: {
    action: 'Allow'
    ipAddress: contains(ipRange, '/') ? ipRange : '${ipRange}/32'
    name: 'AllowDeploymentClient${index}'
    priority: 100 + index
  }
]

resource app 'Microsoft.Web/sites@2023-12-01' = {
  name: appName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: planId
    publicNetworkAccess: (!restrictNetworkAccess || !empty(deploymentClientIpRanges)) ? 'Enabled' : 'Disabled'
    httpsOnly: true
    clientAffinityEnabled: false
    virtualNetworkSubnetId: subnetId
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: packageContainerUri
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      runtime: {
        name: 'dotnet-isolated'
        version: '10.0'
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 10
        instanceMemoryMB: 2048
      }
    }
    siteConfig: {
      appSettings: appSettings
      ftpsState: 'Disabled'
      http20Enabled: true
      ipSecurityRestrictions: restrictNetworkAccess ? deploymentAccessRules : []
      ipSecurityRestrictionsDefaultAction: restrictNetworkAccess ? 'Deny' : 'Allow'
      minTlsVersion: '1.2'
      scmIpSecurityRestrictions: restrictNetworkAccess ? deploymentAccessRules : []
      scmIpSecurityRestrictionsDefaultAction: restrictNetworkAccess ? 'Deny' : 'Allow'
      scmIpSecurityRestrictionsUseMain: false
      scmMinTlsVersion: '1.2'
      vnetRouteAllEnabled: true
    }
  }
}

output id string = app.id
output name string = app.name
output principalId string = app.identity.principalId
output defaultHostName string = app.properties.defaultHostName
