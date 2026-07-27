targetScope = 'subscription'

@description('Short workload name used in resource names.')
@minLength(3)
@maxLength(18)
param workloadName string = 'expenseflow'

@description('Tags applied to all resource groups and workload resources.')
param tags object = {}

@description('Optional public IPv4 ranges allowed through the storage firewall for developer deployment access. Leave empty to disable public network access.')
param deploymentClientIpRanges array = []

@description('When true, applies the private-only network baseline. Set false temporarily for deployment/debugging.')
param restrictNetworkAccess bool = true

@description('When true, writes the current OCR Function host key to Key Vault.')
param updateOcrFunctionKeySecret bool = true

@description('When true, allows public Azure Monitor query access for demo health-model queries while keeping ingestion private.')
param allowPublicMonitorQueryAccess bool = false

@description('Optional name for the health model resource. When empty, a name is generated automatically.')
param healthModelName string = ''

@description('Resource group deployments. Add more entries for future multi-region deployments.')
param deployments array = [
  {
    name: 'primary'
    resourceGroupName: 'rg-expenseflow-demo'
    location: 'westeurope'
    environmentName: 'demo'
  }
]

resource resourceGroups 'Microsoft.Resources/resourceGroups@2022-09-01' = [for deployment in deployments: {
  name: deployment.resourceGroupName
  location: deployment.location
  tags: union(tags, {
    workload: workloadName
    environment: deployment.environmentName
    deployment: deployment.name
  })
}]

module workloadDeployments 'main.bicep' = [for (deployment, index) in deployments: {
  name: 'workload-${deployment.name}-${uniqueString(subscription().id, deployment.resourceGroupName)}'
  scope: resourceGroups[index]
  params: {
    location: deployment.location
    workloadName: workloadName
    environmentName: deployment.environmentName
    deploymentClientIpRanges: deploymentClientIpRanges
    restrictNetworkAccess: restrictNetworkAccess
    updateOcrFunctionKeySecret: updateOcrFunctionKeySecret
    allowPublicMonitorQueryAccess: allowPublicMonitorQueryAccess
    healthModelName: healthModelName
    tags: union(tags, {
      deployment: deployment.name
    })
  }
}]

output resourceGroupNames array = [for deployment in deployments: deployment.resourceGroupName]
output healthModelResourceIds array = [for (deployment, index) in deployments: workloadDeployments[index].outputs.healthModelResourceId]
output healthModelAnnotationMaps array = [for (deployment, index) in deployments: workloadDeployments[index].outputs.healthModelAnnotationMap]
