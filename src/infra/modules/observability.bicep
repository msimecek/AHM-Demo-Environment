@description('Azure region for observability resources.')
param location string

@description('Log Analytics workspace name.')
param workspaceName string

@description('Application Insights component name.')
param applicationInsightsName string

@description('Azure Monitor Private Link Scope name.')
param privateLinkScopeName string

@description('Tags applied to observability resources.')
param tags object

@description('When true, disables public ingestion/query access where supported.')
param restrictNetworkAccess bool = true

@description('When true, allows public Azure Monitor query access for demo health-model queries while keeping ingestion private.')
param allowPublicMonitorQueryAccess bool = false

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: restrictNetworkAccess ? 'Disabled' : 'Enabled'
    publicNetworkAccessForQuery: (!restrictNetworkAccess || allowPublicMonitorQueryAccess) ? 'Enabled' : 'Disabled'
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    DisableLocalAuth: true
    IngestionMode: 'LogAnalytics'
    WorkspaceResourceId: workspace.id
    publicNetworkAccessForIngestion: restrictNetworkAccess ? 'Disabled' : 'Enabled'
    publicNetworkAccessForQuery: (!restrictNetworkAccess || allowPublicMonitorQueryAccess) ? 'Enabled' : 'Disabled'
  }
}

resource privateLinkScope 'Microsoft.Insights/privateLinkScopes@2021-07-01-preview' = {
  name: privateLinkScopeName
  location: 'global'
  tags: tags
  properties: {
    accessModeSettings: {
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: allowPublicMonitorQueryAccess ? 'Open' : 'PrivateOnly'
    }
  }
}

resource workspaceScopedResource 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  name: 'workspace'
  parent: privateLinkScope
  properties: {
    linkedResourceId: workspace.id
  }
}

resource applicationInsightsScopedResource 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  name: 'application-insights'
  parent: privateLinkScope
  properties: {
    linkedResourceId: applicationInsights.id
  }
}

output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
output applicationInsightsId string = applicationInsights.id
output applicationInsightsName string = applicationInsights.name
output privateLinkScopeId string = privateLinkScope.id
output workspaceId string = workspace.id
output workspaceName string = workspace.name
