targetScope = 'resourceGroup'

@description('Health Model resource name.')
param healthModelName string

@description('Azure region for the Health Model resource.')
param location string = resourceGroup().location

@description('Tags applied to the Health Model resource.')
param tags object = {}

@description('Storage account resource ID.')
param storageAccountResourceId string

@description('Secondary storage account resource ID.')
param secondaryStorageAccountResourceId string

@description('Worker Function App resource ID.')
param workerFunctionResourceId string

@description('Log Analytics workspace resource ID.')
param logAnalyticsWorkspaceResourceId string

@description('BFF Flex plan resource ID.')
param bffPlanResourceId string

@description('OCR Function App resource ID.')
param ocrFunctionResourceId string

@description('BFF Function App resource ID.')
param bffFunctionResourceId string

@description('OCR Flex plan resource ID.')
param ocrPlanResourceId string

@description('Worker Flex plan resource ID.')
param workerPlanResourceId string

@description('Key Vault resource ID.')
param keyVaultResourceId string

@description('Service Bus namespace resource ID.')
param serviceBusNamespaceResourceId string

@description('Cosmos DB account resource ID.')
param cosmosAccountResourceId string

@description('Application Insights role name for the BFF Function App.')
param bffAppRoleName string

@description('Application Insights role name for the Worker Function App.')
param workerAppRoleName string

@description('Application Insights role name for the OCR Function App.')
param ocrAppRoleName string

@description('Entity name used for the external OCR provider.')
param externalOcrProviderEntityName string = 'external-ocr-provider'

@description('Signal name used for externally reported OCR provider availability.')
param externalOcrProviderSignalName string = 'external-ocr-provider-availability'

resource healthModel 'Microsoft.CloudHealth/healthmodels@2026-05-01-preview' = {
  name: healthModelName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

resource authenticationSettingSystemAssigned 'Microsoft.CloudHealth/healthmodels/authenticationsettings@2026-05-01-preview' = {
  parent: healthModel
  name: 'systemassigned'
  properties: {
    authenticationKind: 'ManagedIdentity'
    displayName: 'SystemAssigned'
    managedIdentityName: 'SystemAssigned'
  }
}

resource discoveryRulePolicyConfig 'Microsoft.CloudHealth/healthmodels/discoveryrules@2026-05-01-preview' = {
  parent: healthModel
  name: 'regional-policy-config'
  properties: {
    displayName: 'Regional configuration stores'
    authenticationSetting: 'systemassigned'
    discoverRelationships: 'Enabled'
    addRecommendedSignals: 'Enabled'
    addResourceHealthSignal: 'Enabled'
    specification: {
      kind: 'ResourceGraphQuery'
      resourceGraphQuery: 'resources | where type =~ \'microsoft.appconfiguration/configurationstores\' and tags[\'component\'] =~ \'policy-config\''
    }
  }
  dependsOn: [
    authenticationSettingSystemAssigned
  ]
}


resource signalDefinitionAspHttpQueueLength 'Microsoft.CloudHealth/healthmodels/signaldefinitions@2026-05-01-preview' = {
  parent: healthModel
  name: 'b1f31305-a9d4-4205-b98a-c8a387680602'
  properties: {
    aggregationType: 'Average'
    dataUnit: 'Count'
    displayName: 'ASP - Http Queue Length'
    evaluationRules: {
      degradedRule: {
        operator: 'GreaterThan'
        threshold: 10
      }
      unhealthyRule: {
        operator: 'GreaterThan'
        threshold: 50
      }
    }
    metricName: 'HttpQueueLength'
    metricNamespace: 'microsoft.web/serverfarms'
    refreshInterval: 'PT1M'
    signalKind: 'AzureResourceMetric'
    timeGrain: 'PT1M'
  }
}

resource signalDefinitionStorageClientAuthErrors 'Microsoft.CloudHealth/healthmodels/signaldefinitions@2026-05-01-preview' = {
  parent: healthModel
  name: 'b30854b5-c14c-4cb2-8493-ea4f1fe239bf'
  properties: {
    aggregationType: 'Total'
    dataUnit: 'Count'
    dimensionFilter: 'ResponseType eq \'ClientOtherError\''
    displayName: 'Client/auth errors'
    evaluationRules: {
      degradedRule: {
        operator: 'GreaterThan'
        threshold: 5
      }
      unhealthyRule: {
        operator: 'GreaterThan'
        threshold: 25
      }
    }
    metricName: 'Transactions'
    metricNamespace: 'microsoft.storage/storageaccounts'
    refreshInterval: 'PT1M'
    signalKind: 'AzureResourceMetric'
    timeGrain: 'PT5M'
  }
}

resource signalDefinitionStorageAuthorizationErrors 'Microsoft.CloudHealth/healthmodels/signaldefinitions@2026-05-01-preview' = {
  parent: healthModel
  name: '63ad959b-39f1-4deb-be18-2d9eafcc1ba4'
  properties: {
    aggregationType: 'Total'
    dataUnit: 'Count'
    dimensionFilter: 'ResponseType eq \'AuthorizationError\''
    displayName: 'AuthorizationError Transations'
    evaluationRules: {
      degradedRule: {
        operator: 'GreaterThan'
        threshold: 0
      }
      unhealthyRule: {
        operator: 'GreaterThan'
        threshold: 5
      }
    }
    metricName: 'Transactions'
    metricNamespace: 'microsoft.storage/storageaccounts'
    refreshInterval: 'PT1M'
    signalKind: 'AzureResourceMetric'
    timeGrain: 'PT5M'
  }
}

resource signalDefinitionStorageSuccessE2ELatency 'Microsoft.CloudHealth/healthmodels/signaldefinitions@2026-05-01-preview' = {
  parent: healthModel
  name: '808a5d79-5c9c-4b28-8217-05019e40acfd'
  properties: {
    aggregationType: 'Average'
    dataUnit: 'MilliSeconds'
    displayName: 'Success E2E Latency'
    evaluationRules: {
      degradedRule: {
        operator: 'GreaterThan'
        threshold: 100
      }
      unhealthyRule: {
        operator: 'GreaterThan'
        threshold: 200
      }
    }
    metricName: 'SuccessE2ELatency'
    metricNamespace: 'microsoft.storage/storageaccounts'
    refreshInterval: 'PT1M'
    signalKind: 'AzureResourceMetric'
    timeGrain: 'PT5M'
  }
}

resource signalDefinitionStorageAvailability 'Microsoft.CloudHealth/healthmodels/signaldefinitions@2026-05-01-preview' = {
  parent: healthModel
  name: '7de1a349-dd82-4c4d-9215-232165d8a8ca'
  properties: {
    aggregationType: 'Minimum'
    dataUnit: 'Percent'
    displayName: 'Availability'
    evaluationRules: {
      degradedRule: {
        operator: 'LessThan'
        threshold: 95
      }
      unhealthyRule: {
        operator: 'LessThan'
        threshold: 90
      }
    }
    metricName: 'Availability'
    metricNamespace: 'microsoft.storage/storageaccounts'
    refreshInterval: 'PT1M'
    signalKind: 'AzureResourceMetric'
    timeGrain: 'PT5M'
  }
}


resource entityPrimaryStorage 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: '09a5fd7d-a108-4b2d-a377-6d06266e18fd'
  properties: {
    canvasPosition: {
      x: -440
      y: 940
    }
    displayName: 'Primary Storage'
    icon: {
      iconName: 'Resource'
    }
    impact: 'Standard'
    signalGroups: {
      azureResource: {
        authenticationSetting: 'systemassigned'
        azureResourceId: storageAccountResourceId
        signals: [
          {
            name: 'b30854b5-c14c-4cb2-8493-ea4f1fe239bf'
            signalDefinitionName: 'b30854b5-c14c-4cb2-8493-ea4f1fe239bf'
            signalKind: 'AzureResourceMetric'
          }
          {
            name: '63ad959b-39f1-4deb-be18-2d9eafcc1ba4'
            signalDefinitionName: '63ad959b-39f1-4deb-be18-2d9eafcc1ba4'
            signalKind: 'AzureResourceMetric'
          }
          {
            name: '808a5d79-5c9c-4b28-8217-05019e40acfd'
            signalDefinitionName: '808a5d79-5c9c-4b28-8217-05019e40acfd'
            signalKind: 'AzureResourceMetric'
          }
          {
            name: '7de1a349-dd82-4c4d-9215-232165d8a8ca'
            signalDefinitionName: '7de1a349-dd82-4c4d-9215-232165d8a8ca'
            signalKind: 'AzureResourceMetric'
          }
        ]
        resourceHealth: {
          enabled: 'Enabled'
        }
      }
    }
    tags: {}
  }
  dependsOn: [
    authenticationSettingSystemAssigned
    signalDefinitionAspHttpQueueLength
    signalDefinitionStorageClientAuthErrors
    signalDefinitionStorageAuthorizationErrors
    signalDefinitionStorageSuccessE2ELatency
    signalDefinitionStorageAvailability
  ]
}

resource entitySecondaryStorage 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: 'f2a40f5e-52b2-48a2-96ce-33f4d884825d'
  properties: {
    canvasPosition: {
      x: -210
      y: 940
    }
    displayName: 'Secondary Storage'
    icon: {
      iconName: 'Resource'
    }
    impact: 'Standard'
    signalGroups: {
      azureResource: {
        authenticationSetting: 'systemassigned'
        azureResourceId: secondaryStorageAccountResourceId
        signals: [
          {
            name: 'c4f0ba3e-4247-469a-942e-8836aeac13ad'
            signalDefinitionName: 'b30854b5-c14c-4cb2-8493-ea4f1fe239bf'
            signalKind: 'AzureResourceMetric'
          }
          {
            name: 'e99c6d50-2f39-4f44-97e4-23010ed2255f'
            signalDefinitionName: '63ad959b-39f1-4deb-be18-2d9eafcc1ba4'
            signalKind: 'AzureResourceMetric'
          }
          {
            name: 'dd8516cd-fc93-4818-a43d-477a109dbf3e'
            signalDefinitionName: '808a5d79-5c9c-4b28-8217-05019e40acfd'
            signalKind: 'AzureResourceMetric'
          }
          {
            name: 'e7ea4276-8d9e-4408-b8f3-460cfb4ad42a'
            signalDefinitionName: '7de1a349-dd82-4c4d-9215-232165d8a8ca'
            signalKind: 'AzureResourceMetric'
          }
        ]
        resourceHealth: {
          enabled: 'Enabled'
        }
      }
    }
    tags: {}
  }
  dependsOn: [
    authenticationSettingSystemAssigned
    signalDefinitionAspHttpQueueLength
    signalDefinitionStorageClientAuthErrors
    signalDefinitionStorageAuthorizationErrors
    signalDefinitionStorageSuccessE2ELatency
    signalDefinitionStorageAvailability
  ]
}

resource entityWorker 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: '0beddc06-19ae-4061-b104-0152c3e5dd8d'
  properties: {
    canvasPosition: {
      x: 120
      y: 770
    }
    displayName: 'Worker'
    icon: {
      iconName: 'Resource'
    }
    impact: 'Standard'
    signalGroups: {
      azureLogAnalytics: {
        authenticationSetting: 'systemassigned'
        logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
        signals: [
          {
            displayName: 'OCR failures'
            evaluationRules: {
              degradedRule: {
                operator: 'GreaterThan'
                threshold: 0
              }
              unhealthyRule: {
                operator: 'GreaterThan'
                threshold: 5
              }
            }
            name: '7288143a-61be-42a0-bbda-02f5a549c7d3'
            queryText: format('''
AppDependencies
| where TimeGenerated > ago(10m)
| where AppRoleName == "{0}"
| where Name contains "/api/ocr/extract"
| summarize calls=count(), failures=countif(Success == false), p95DurationMs=percentile(DurationMs, 95) by TimeGenerated=bin(TimeGenerated, 5m), DependencyType, Target, Name
| order by TimeGenerated desc
            ''', workerAppRoleName)
            refreshInterval: 'PT1M'
            signalKind: 'LogAnalyticsQuery'
            timeGrain: 'PT30M'
            valueColumnName: 'failures'
          }
          {
            displayName: 'Worker executions'
            evaluationRules: {
              unhealthyRule: {
                operator: 'LessThan'
                threshold: 1
              }
            }
            name: '2e9b8109-d4fe-452f-b9b9-d7b15bd68afe'
            queryText: format('''
AppRequests
| where TimeGenerated > ago(10m)
| where AppRoleName == "{0}"
| where Name == "ProcessExpense"
| summarize
    executions=count(),
    failures=countif(Success == false),
    avgDurationMs=avg(DurationMs),
    p95DurationMs=percentile(DurationMs, 95)
    by bin(TimeGenerated, 5m)
| order by TimeGenerated desc
| take 1
            ''', workerAppRoleName)
            refreshInterval: 'PT1M'
            signalKind: 'LogAnalyticsQuery'
            timeGrain: 'PT30M'
            valueColumnName: 'executions'
          }
        ]
      }
      azureResource: {
        authenticationSetting: 'systemassigned'
        azureResourceId: workerFunctionResourceId
        resourceHealth: {
          enabled: 'Disabled'
        }
      }
    }
    tags: {}
  }
  dependsOn: [
    authenticationSettingSystemAssigned
    signalDefinitionAspHttpQueueLength
  ]
}

resource entityBffPlan 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: '1e6f2190-c66c-4496-a5b5-3287512b59b7'
  properties: {
    canvasPosition: {
      x: -810
      y: 970
    }
    displayName: 'BFF plan'
    icon: {
      iconName: 'Resource'
    }
    impact: 'Standard'
    signalGroups: {
      azureResource: {
        authenticationSetting: 'systemassigned'
        azureResourceId: bffPlanResourceId
        signals: [
          {
            name: 'ca2ba2fc-2ad7-4887-bbca-6dd6d2d14856'
            refreshInterval: 'PT1M'
            signalDefinitionName: 'b1f31305-a9d4-4205-b98a-c8a387680602'
            signalKind: 'AzureResourceMetric'
          }
        ]
        resourceHealth: {
          enabled: 'Disabled'
        }
      }
    }
    tags: {}
  }
  dependsOn: [
    authenticationSettingSystemAssigned
    signalDefinitionAspHttpQueueLength
  ]
}

resource entityApiLayer 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: '5ccf2422-068d-49b9-9586-559368a77a46'
  properties: {
    alerts: {
      unhealthy: {
        description: 'API layer is experiencing a critical failure and requires immediate attention.'
        severity: 'Sev0'
      }
    }
    canvasPosition: {
      x: -510
      y: 370
    }
    displayName: 'API layer'
    icon: {
      iconName: 'SystemComponent'
    }
    impact: 'Standard'
    tags: {}
  }
  dependsOn: [
    authenticationSettingSystemAssigned
    signalDefinitionAspHttpQueueLength
  ]
}

resource entityOcr 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: '63733205-1535-44ff-8962-6bad4e0aa0ee'
  properties: {
    canvasPosition: {
      x: 370
      y: 770
    }
    displayName: 'OCR'
    icon: {
      iconName: 'Resource'
    }
    impact: 'Standard'
    signalGroups: {
      azureLogAnalytics: {
        authenticationSetting: 'systemassigned'
        logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
        signals: [
          {
            dataUnit: 'ms'
            displayName: 'OCR duration'
            evaluationRules: {
              degradedRule: {
                operator: 'GreaterThan'
                threshold: 1000
              }
              unhealthyRule: {
                operator: 'GreaterThan'
                threshold: 2000
              }
            }
            name: 'a5396b76-6d06-4602-9463-da1bff0d3d9f'
            queryText: format('''
AppRequests
| where TimeGenerated > ago(10m)
| where AppRoleName == "{0}"
| where Name == "ExtractReceipt"
| summarize
    executions=count(),
    failures=countif(Success == false),
    avgDurationMs=avg(DurationMs),
    p95DurationMs=percentile(DurationMs, 95)
    by bin(TimeGenerated, 5m)
| order by TimeGenerated desc
| take 1
            ''', ocrAppRoleName)
            refreshInterval: 'PT1M'
            signalKind: 'LogAnalyticsQuery'
            timeGrain: 'PT30M'
            valueColumnName: 'avgDurationMs'
          }
        ]
      }
      azureResource: {
        authenticationSetting: 'systemassigned'
        azureResourceId: ocrFunctionResourceId
        resourceHealth: {
          enabled: 'Disabled'
        }
      }
    }
    tags: {}
  }
  dependsOn: [
    authenticationSettingSystemAssigned
    signalDefinitionAspHttpQueueLength
  ]
}

resource entityExternalOcrProvider 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: externalOcrProviderEntityName
  properties: {
    canvasPosition: {
      x: 630
      y: 970
    }
    displayName: 'OCR provider (external)'
    icon: {
      iconName: 'Generic'
    }
    impact: 'Standard'
    tags: {
      component: 'external-ocr-provider'
      signalName: externalOcrProviderSignalName
    }
  }
  dependsOn: [
    authenticationSettingSystemAssigned
  ]
}

resource entityManagementLayer 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: '72dbfe59-ddc0-4b40-85c4-16ac53262023'
  properties: {
    alerts: {
      unhealthy: {
        description: 'Management layer is experiencing a critical failure and requires immediate attention.'
        severity: 'Sev0'
      }
    }
    canvasPosition: {
      x: 910
      y: 370
    }
    displayName: 'Management layer'
    icon: {
      iconName: 'SystemComponent'
    }
    impact: 'Standard'
    tags: {}
  }
  dependsOn: [
    authenticationSettingSystemAssigned
    signalDefinitionAspHttpQueueLength
  ]
}

resource entityBff 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: '7896a212-ac11-4b4a-a81d-99e3fd666b8d'
  properties: {
    canvasPosition: {
      x: -810
      y: 770
    }
    displayName: 'BFF'
    icon: {
      iconName: 'Resource'
    }
    impact: 'Standard'
    signalGroups: {
      azureLogAnalytics: {
        authenticationSetting: 'systemassigned'
        logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
        signals: [
          {
            displayName: 'Number of exceptions'
            evaluationRules: {
              degradedRule: {
                operator: 'GreaterThan'
                threshold: 0
              }
              unhealthyRule: {
                operator: 'GreaterThan'
                threshold: 0
              }
            }
            name: 'ad3f113b-ce2c-4fad-a673-3965f099bec6'
            queryText: format('''
AppExceptions
| where TimeGenerated > ago(10m)
| where AppRoleName == "{0}"
| summarize exceptions=count()
            ''', bffAppRoleName)
            refreshInterval: 'PT1M'
            signalKind: 'LogAnalyticsQuery'
            timeGrain: 'PT30M'
            valueColumnName: 'exceptions'
          }
        ]
      }
      azureResource: {
        authenticationSetting: 'systemassigned'
        azureResourceId: bffFunctionResourceId
        resourceHealth: {
          enabled: 'Disabled'
        }
      }
    }
    tags: {}
  }
  dependsOn: [
    authenticationSettingSystemAssigned
    signalDefinitionAspHttpQueueLength
  ]
}

resource entityDataLayer 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: '839e8a4f-5b08-467c-aed8-56bd07f72db1'
  properties: {
    canvasPosition: {
      x: -260
      y: 570
    }
    displayName: 'Data layer'
    icon: {
      iconName: 'SystemComponent'
    }
    impact: 'Standard'
    tags: {}
  }
  dependsOn: [
    authenticationSettingSystemAssigned
    signalDefinitionAspHttpQueueLength
  ]
}

resource entityStorageAccounts 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: '063cfc66-b335-41b2-a983-27d31c1978c1'
  properties: {
    canvasPosition: {
      x: -310
      y: 770
    }
    displayName: 'Storage accounts'
    icon: {
      iconName: 'Generic'
    }
    impact: 'Standard'
    tags: {}
    signalGroups: {
      dependencies: {
        aggregationType: 'MinHealthy'
        degradedThreshold: 1
        unhealthyThreshold: 0
        unit: 'Absolute'
        ignoreUnknown: false
      }
    }
  }
  dependsOn: [
    authenticationSettingSystemAssigned
    signalDefinitionAspHttpQueueLength
  ]
}

resource entityOcrPlan 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: '936421d2-c8cd-4186-a2f2-07147209c051'
  properties: {
    canvasPosition: {
      x: 370
      y: 970
    }
    displayName: 'OCR plan'
    icon: {
      iconName: 'Resource'
    }
    impact: 'Standard'
    signalGroups: {
      azureResource: {
        authenticationSetting: 'systemassigned'
        azureResourceId: ocrPlanResourceId
        signals: [
          {
            name: 'c1a66164-1b54-4f29-ba1b-92b4852a804c'
            refreshInterval: 'PT1M'
            signalDefinitionName: 'b1f31305-a9d4-4205-b98a-c8a387680602'
            signalKind: 'AzureResourceMetric'
          }
        ]
        resourceHealth: {
          enabled: 'Disabled'
        }
      }
    }
    tags: {}
  }
  dependsOn: [
    authenticationSettingSystemAssigned
    signalDefinitionAspHttpQueueLength
  ]
}

resource entityWorkerPlan 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: 'af71d029-9644-49f1-a6bf-fcb5d3f12766'
  properties: {
    canvasPosition: {
      x: 120
      y: 970
    }
    displayName: 'Worker plan'
    icon: {
      iconName: 'Resource'
    }
    impact: 'Standard'
    signalGroups: {
      azureResource: {
        authenticationSetting: 'systemassigned'
        azureResourceId: workerPlanResourceId
        signals: [
          {
            name: '38b5098e-bdad-4e4a-a293-a51fc9d11c54'
            refreshInterval: 'PT1M'
            signalDefinitionName: 'b1f31305-a9d4-4205-b98a-c8a387680602'
            signalKind: 'AzureResourceMetric'
          }
        ]
        resourceHealth: {
          enabled: 'Disabled'
        }
      }
    }
    tags: {}
  }
  dependsOn: [
    authenticationSettingSystemAssigned
    signalDefinitionAspHttpQueueLength
  ]
}

resource entityProcessingLayer 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: 'ccae2486-2116-4734-adc0-7c238458b6fb'
  properties: {
    alerts: {
      unhealthy: {
        description: 'Processing layer is experiencing a critical failure and requires immediate attention.'
        severity: 'Sev0'
      }
    }
    canvasPosition: {
      x: -10
      y: 370
    }
    displayName: 'Processing layer'
    icon: {
      iconName: 'SystemComponent'
    }
    impact: 'Standard'
    tags: {}
  }
  dependsOn: [
    authenticationSettingSystemAssigned
    signalDefinitionAspHttpQueueLength
  ]
}

resource entityKeyVault 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: 'cd59fe0e-0ccf-4471-959b-9995cec4f206'
  properties: {
    canvasPosition: {
      x: 620
      y: 770
    }
    displayName: 'Key Vault'
    icon: {
      iconName: 'Resource'
    }
    impact: 'Standard'
    signalGroups: {
      azureResource: {
        authenticationSetting: 'systemassigned'
        azureResourceId: keyVaultResourceId
        signals: [
          {
            aggregationType: 'Average'
            dataUnit: 'Percent'
            displayName: 'Overall Vault Availability'
            evaluationRules: {
              degradedRule: {
                operator: 'LessThan'
                threshold: 99
              }
              unhealthyRule: {
                operator: 'LessThan'
                threshold: 95
              }
            }
            metricName: 'Availability'
            metricNamespace: 'microsoft.keyvault/vaults'
            name: 'f1c63a2e-84f7-4608-b0ab-4a5f66dee016'
            refreshInterval: 'PT1M'
            signalKind: 'AzureResourceMetric'
            timeGrain: 'PT30M'
          }
          {
            aggregationType: 'Average'
            dataUnit: 'MilliSeconds'
            displayName: 'Overall Service Api Latency'
            evaluationRules: {
              degradedRule: {
                operator: 'GreaterThan'
                threshold: 50
              }
              unhealthyRule: {
                operator: 'GreaterThan'
                threshold: 100
              }
            }
            metricName: 'ServiceApiLatency'
            metricNamespace: 'microsoft.keyvault/vaults'
            name: 'e747b245-b9b2-49b3-95a9-f177e455bfc6'
            refreshInterval: 'PT1M'
            signalKind: 'AzureResourceMetric'
            timeGrain: 'PT15M'
          }
        ]
        resourceHealth: {
          enabled: 'Enabled'
        }
      }
    }
    tags: {}
  }
  dependsOn: [
    authenticationSettingSystemAssigned
    signalDefinitionAspHttpQueueLength
  ]
}

resource entityServiceBus 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: 'ddcb4be3-b81d-4b99-8de9-529ee191671a'
  properties: {
    canvasPosition: {
      x: -530
      y: 770
    }
    displayName: 'Service Bus'
    icon: {
      iconName: 'Resource'
    }
    impact: 'Standard'
    signalGroups: {
      azureResource: {
        authenticationSetting: 'systemassigned'
        azureResourceId: serviceBusNamespaceResourceId
        signals: [
          {
            aggregationType: 'Maximum'
            dataUnit: 'Percent'
            displayName: 'CPU'
            evaluationRules: {
              degradedRule: {
                operator: 'GreaterThan'
                threshold: 20
              }
              unhealthyRule: {
                operator: 'GreaterThan'
                threshold: 50
              }
            }
            metricName: 'NamespaceCpuUsage'
            metricNamespace: 'microsoft.servicebus/namespaces'
            name: '8648c9a4-f234-46f9-822a-a78ec060d50d'
            refreshInterval: 'PT1M'
            signalKind: 'AzureResourceMetric'
            timeGrain: 'PT5M'
          }
          {
            aggregationType: 'Maximum'
            dataUnit: 'Count'
            displayName: 'Count of active messages in a Queue/Topic.'
            evaluationRules: {
              degradedRule: {
                operator: 'GreaterThan'
                threshold: 5
              }
              unhealthyRule: {
                operator: 'GreaterThan'
                threshold: 10
              }
            }
            metricName: 'ActiveMessages'
            metricNamespace: 'microsoft.servicebus/namespaces'
            name: 'd4a0fa86-217d-41e4-ba52-ead1af082d6a'
            refreshInterval: 'PT1M'
            signalKind: 'AzureResourceMetric'
            timeGrain: 'PT1M'
          }
          {
            aggregationType: 'Total'
            dataUnit: 'Count'
            displayName: 'Abandoned Messages'
            evaluationRules: {
              unhealthyRule: {
                operator: 'GreaterThan'
                threshold: 0
              }
            }
            metricName: 'AbandonMessage'
            metricNamespace: 'microsoft.servicebus/namespaces'
            name: '30e2e566-04a1-4411-adbe-ac692684799a'
            refreshInterval: 'PT1M'
            signalKind: 'AzureResourceMetric'
            timeGrain: 'PT1M'
          }
        ]
        resourceHealth: {
          enabled: 'Enabled'
        }
      }
    }
    tags: {}
  }
  dependsOn: [
    authenticationSettingSystemAssigned
    signalDefinitionAspHttpQueueLength
  ]
}

resource entityCosmos 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: 'e69e768b-0355-49c6-9451-b94ced3046c8'
  properties: {
    canvasPosition: {
      x: -100
      y: 770
    }
    displayName: 'Cosmos'
    icon: {
      iconName: 'Resource'
    }
    impact: 'Standard'
    signalGroups: {
      azureResource: {
        authenticationSetting: 'systemassigned'
        azureResourceId: cosmosAccountResourceId
        signals: [
          {
            aggregationType: 'Average'
            dataUnit: 'Percent'
            displayName: 'Service Availability'
            evaluationRules: {
              degradedRule: {
                operator: 'LessThan'
                threshold: 95
              }
              unhealthyRule: {
                operator: 'LessThan'
                threshold: 90
              }
            }
            metricName: 'ServiceAvailability'
            metricNamespace: 'microsoft.documentdb/databaseaccounts'
            name: '67a4e6ec-482d-493f-8d25-f7f48f58d97d'
            refreshInterval: 'PT1M'
            signalKind: 'AzureResourceMetric'
            timeGrain: 'PT1H'
          }
          {
            aggregationType: 'Count'
            dataUnit: 'Count'
            displayName: 'Total Requests'
            evaluationRules: {
              degradedRule: {
                operator: 'LessThan'
                threshold: 2
              }
              unhealthyRule: {
                operator: 'Equal'
                threshold: 0
              }
            }
            metricName: 'TotalRequests'
            metricNamespace: 'microsoft.documentdb/databaseaccounts'
            name: 'af9392d4-566b-442c-aea9-84b6774897b6'
            refreshInterval: 'PT1M'
            signalKind: 'AzureResourceMetric'
            timeGrain: 'PT5M'
          }
          {
            aggregationType: 'Average'
            dataUnit: 'MilliSeconds'
            dimensionFilter: 'OperationType eq \'Upsert\''
            displayName: 'Server Side Latency Direct'
            evaluationRules: {
              degradedRule: {
                operator: 'GreaterThan'
                threshold: 20
              }
              unhealthyRule: {
                operator: 'GreaterThan'
                threshold: 200
              }
            }
            metricName: 'ServerSideLatencyDirect'
            metricNamespace: 'microsoft.documentdb/databaseaccounts'
            name: 'bb73f2a2-3c50-46e2-8b20-e93dbd7483fb'
            refreshInterval: 'PT1M'
            signalKind: 'AzureResourceMetric'
            timeGrain: 'PT5M'
          }
          {
            aggregationType: 'Maximum'
            dataUnit: 'Percent'
            displayName: 'Normalized RU Consumption'
            evaluationRules: {
              degradedRule: {
                operator: 'GreaterThan'
                threshold: 70
              }
              unhealthyRule: {
                operator: 'GreaterThan'
                threshold: 90
              }
            }
            metricName: 'NormalizedRUConsumption'
            metricNamespace: 'microsoft.documentdb/databaseaccounts'
            name: 'be4a8b12-218c-41a1-91d6-bac1354748da'
            refreshInterval: 'PT1M'
            signalKind: 'AzureResourceMetric'
            timeGrain: 'PT5M'
          }
        ]
        resourceHealth: {
          enabled: 'Enabled'
        }
      }
    }
    tags: {}
  }
  dependsOn: [
    authenticationSettingSystemAssigned
    signalDefinitionAspHttpQueueLength
  ]
}

resource entityKeepAliveFunc 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: 'f41a6637-9904-401b-8aba-6fc70b8226c8'
  properties: {
    canvasPosition: {
      x: 910
      y: 760
    }
    displayName: 'Keep alive func'
    icon: {
      iconName: 'Resource'
    }
    impact: 'Standard'
    signalGroups: {
      azureResource: {
        authenticationSetting: 'systemassigned'
        azureResourceId: bffFunctionResourceId
        signals: [
          {
            aggregationType: 'Count'
            dataUnit: 'Count'
            displayName: 'On Demand Function Execution Count'
            evaluationRules: {
              degradedRule: {
                operator: 'LessThan'
                threshold: 2
              }
              unhealthyRule: {
                operator: 'LessThan'
                threshold: 1
              }
            }
            metricName: 'OnDemandFunctionExecutionCount'
            metricNamespace: 'microsoft.web/sites'
            name: '60becc52-88da-4308-9d4a-5268a2223f1e'
            refreshInterval: 'PT1M'
            signalKind: 'AzureResourceMetric'
            timeGrain: 'PT5M'
          }
        ]
        resourceHealth: {
          enabled: 'Disabled'
        }
      }
    }
    tags: {}
  }
  dependsOn: [
    authenticationSettingSystemAssigned
    signalDefinitionAspHttpQueueLength
  ]
}

resource entitySubmitExpenses 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: 'fc3e84a3-7c3a-4aff-b148-e764d3c71276'
  properties: {
    canvasPosition: {
      x: 0
      y: 150
    }
    displayName: 'Submit expenses'
    icon: {
      iconName: 'UserFlow'
    }
    impact: 'Standard'
    tags: {}
  }
  dependsOn: [
    authenticationSettingSystemAssigned
    signalDefinitionAspHttpQueueLength
  ]
}

resource entityExpenseFlowApplication 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  parent: healthModel
  name: healthModelName
  properties: {
    canvasPosition: {
      x: 0
      y: 0
    }
    displayName: 'ExpenseFlow Application'
    healthObjective: json('99.99')
    impact: 'Standard'
    tags: {}
  }
  dependsOn: [
    authenticationSettingSystemAssigned
    signalDefinitionAspHttpQueueLength
  ]
}

resource relationshipWorkerToWorkerPlan 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  parent: healthModel
  name: '0beddc06-19ae-4061-b104-0152c3e5dd8d-af71d029-9644-49f1-a6bf-fcb5d3f12766'
  properties: {
    childEntityName: 'af71d029-9644-49f1-a6bf-fcb5d3f12766'
    parentEntityName: '0beddc06-19ae-4061-b104-0152c3e5dd8d'
  }
  dependsOn: [
    entityPrimaryStorage
    entityWorker
    entityBffPlan
    entityApiLayer
    entityOcr
    entityManagementLayer
    entityBff
    entityDataLayer
    entityOcrPlan
    entityWorkerPlan
    entityProcessingLayer
    entityKeyVault
    entityServiceBus
    entityCosmos
    entityKeepAliveFunc
    entitySubmitExpenses
    entityExpenseFlowApplication
  ]
}

resource relationshipApiLayerToDataLayer 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  parent: healthModel
  name: '1806a2dc-d1e6-4172-a939-6776db839f03'
  properties: {
    childEntityName: '839e8a4f-5b08-467c-aed8-56bd07f72db1'
    parentEntityName: '5ccf2422-068d-49b9-9586-559368a77a46'
  }
  dependsOn: [
    entityPrimaryStorage
    entityWorker
    entityBffPlan
    entityApiLayer
    entityOcr
    entityManagementLayer
    entityBff
    entityDataLayer
    entityOcrPlan
    entityWorkerPlan
    entityProcessingLayer
    entityKeyVault
    entityServiceBus
    entityCosmos
    entityKeepAliveFunc
    entitySubmitExpenses
    entityExpenseFlowApplication
  ]
}

resource relationshipProcessingLayerToDataLayer 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  parent: healthModel
  name: '1f4ff3f5-4dab-48db-8bab-aaa03eac411c'
  properties: {
    childEntityName: '839e8a4f-5b08-467c-aed8-56bd07f72db1'
    parentEntityName: 'ccae2486-2116-4734-adc0-7c238458b6fb'
  }
  dependsOn: [
    entityPrimaryStorage
    entityWorker
    entityBffPlan
    entityApiLayer
    entityOcr
    entityManagementLayer
    entityBff
    entityDataLayer
    entityOcrPlan
    entityWorkerPlan
    entityProcessingLayer
    entityKeyVault
    entityServiceBus
    entityCosmos
    entityKeepAliveFunc
    entitySubmitExpenses
    entityExpenseFlowApplication
  ]
}

resource relationshipApiLayerToBff 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  parent: healthModel
  name: '5ccf2422-068d-49b9-9586-559368a77a46-7896a212-ac11-4b4a-a81d-99e3fd666b8d'
  properties: {
    childEntityName: '7896a212-ac11-4b4a-a81d-99e3fd666b8d'
    parentEntityName: '5ccf2422-068d-49b9-9586-559368a77a46'
  }
  dependsOn: [
    entityPrimaryStorage
    entityWorker
    entityBffPlan
    entityApiLayer
    entityOcr
    entityManagementLayer
    entityBff
    entityDataLayer
    entityOcrPlan
    entityWorkerPlan
    entityProcessingLayer
    entityKeyVault
    entityServiceBus
    entityCosmos
    entityKeepAliveFunc
    entitySubmitExpenses
    entityExpenseFlowApplication
  ]
}

resource relationshipOcrToOcrPlan 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  parent: healthModel
  name: '63733205-1535-44ff-8962-6bad4e0aa0ee-936421d2-c8cd-4186-a2f2-07147209c051'
  properties: {
    childEntityName: '936421d2-c8cd-4186-a2f2-07147209c051'
    parentEntityName: '63733205-1535-44ff-8962-6bad4e0aa0ee'
  }
  dependsOn: [
    entityPrimaryStorage
    entityWorker
    entityBffPlan
    entityApiLayer
    entityOcr
    entityManagementLayer
    entityBff
    entityDataLayer
    entityOcrPlan
    entityWorkerPlan
    entityProcessingLayer
    entityKeyVault
    entityServiceBus
    entityCosmos
    entityKeepAliveFunc
    entitySubmitExpenses
    entityExpenseFlowApplication
  ]
}

resource relationshipOcrToExternalOcrProvider 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  parent: healthModel
  name: '63733205-1535-44ff-8962-6bad4e0aa0ee-${externalOcrProviderEntityName}'
  properties: {
    childEntityName: externalOcrProviderEntityName
    parentEntityName: '63733205-1535-44ff-8962-6bad4e0aa0ee'
  }
  dependsOn: [
    entityOcr
    entityExternalOcrProvider
  ]
}

resource relationshipManagementLayerToKeepAliveFunc 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  parent: healthModel
  name: '72dbfe59-ddc0-4b40-85c4-16ac53262023-f41a6637-9904-401b-8aba-6fc70b8226c8'
  properties: {
    childEntityName: 'f41a6637-9904-401b-8aba-6fc70b8226c8'
    parentEntityName: '72dbfe59-ddc0-4b40-85c4-16ac53262023'
  }
  dependsOn: [
    entityPrimaryStorage
    entityWorker
    entityBffPlan
    entityApiLayer
    entityOcr
    entityManagementLayer
    entityBff
    entityDataLayer
    entityOcrPlan
    entityWorkerPlan
    entityProcessingLayer
    entityKeyVault
    entityServiceBus
    entityCosmos
    entityKeepAliveFunc
    entitySubmitExpenses
    entityExpenseFlowApplication
  ]
}

resource relationshipBffToBffPlan 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  parent: healthModel
  name: '7896a212-ac11-4b4a-a81d-99e3fd666b8d-1e6f2190-c66c-4496-a5b5-3287512b59b7'
  properties: {
    childEntityName: '1e6f2190-c66c-4496-a5b5-3287512b59b7'
    parentEntityName: '7896a212-ac11-4b4a-a81d-99e3fd666b8d'
  }
  dependsOn: [
    entityPrimaryStorage
    entityWorker
    entityBffPlan
    entityApiLayer
    entityOcr
    entityManagementLayer
    entityBff
    entityDataLayer
    entityOcrPlan
    entityWorkerPlan
    entityProcessingLayer
    entityKeyVault
    entityServiceBus
    entityCosmos
    entityKeepAliveFunc
    entitySubmitExpenses
    entityExpenseFlowApplication
  ]
}

resource relationshipSubmitExpensesToApiLayer 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  parent: healthModel
  name: '78cd80dc-9d8d-4587-b8b3-7da830d6016e'
  properties: {
    childEntityName: '5ccf2422-068d-49b9-9586-559368a77a46'
    parentEntityName: 'fc3e84a3-7c3a-4aff-b148-e764d3c71276'
  }
  dependsOn: [
    entityPrimaryStorage
    entityWorker
    entityBffPlan
    entityApiLayer
    entityOcr
    entityManagementLayer
    entityBff
    entityDataLayer
    entityOcrPlan
    entityWorkerPlan
    entityProcessingLayer
    entityKeyVault
    entityServiceBus
    entityCosmos
    entityKeepAliveFunc
    entitySubmitExpenses
    entityExpenseFlowApplication
  ]
}

resource relationshipDataLayerToServiceBus 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  parent: healthModel
  name: '7adbe2d7-f53b-4440-8e35-18fbe004e6a1'
  properties: {
    childEntityName: 'ddcb4be3-b81d-4b99-8de9-529ee191671a'
    parentEntityName: '839e8a4f-5b08-467c-aed8-56bd07f72db1'
  }
  dependsOn: [
    entityPrimaryStorage
    entityWorker
    entityBffPlan
    entityApiLayer
    entityOcr
    entityManagementLayer
    entityBff
    entityDataLayer
    entityOcrPlan
    entityWorkerPlan
    entityProcessingLayer
    entityKeyVault
    entityServiceBus
    entityCosmos
    entityKeepAliveFunc
    entitySubmitExpenses
    entityExpenseFlowApplication
  ]
}

resource relationshipSubmitExpensesToProcessingLayer 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  parent: healthModel
  name: '8187fa36-8443-4c99-9183-53ac5483b128'
  properties: {
    childEntityName: 'ccae2486-2116-4734-adc0-7c238458b6fb'
    parentEntityName: 'fc3e84a3-7c3a-4aff-b148-e764d3c71276'
  }
  dependsOn: [
    entityPrimaryStorage
    entityWorker
    entityBffPlan
    entityApiLayer
    entityOcr
    entityManagementLayer
    entityBff
    entityDataLayer
    entityOcrPlan
    entityWorkerPlan
    entityProcessingLayer
    entityKeyVault
    entityServiceBus
    entityCosmos
    entityKeepAliveFunc
    entitySubmitExpenses
    entityExpenseFlowApplication
  ]
}

resource relationshipDataLayerToStorageAccounts 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  parent: healthModel
  name: '839e8a4f-5b08-467c-aed8-56bd07f72db1-063cfc66-b335-41b2-a983-27d31c1978c1'
  properties: {
    childEntityName: '063cfc66-b335-41b2-a983-27d31c1978c1'
    parentEntityName: '839e8a4f-5b08-467c-aed8-56bd07f72db1'
  }
  dependsOn: [
    entityStorageAccounts
    entityDataLayer
  ]
}

resource relationshipStorageAccountsToPrimaryStorage 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  parent: healthModel
  name: '063cfc66-b335-41b2-a983-27d31c1978c1-09a5fd7d-a108-4b2d-a377-6d06266e18fd'
  properties: {
    childEntityName: '09a5fd7d-a108-4b2d-a377-6d06266e18fd'
    parentEntityName: '063cfc66-b335-41b2-a983-27d31c1978c1'
  }
  dependsOn: [
    entityPrimaryStorage
    entityStorageAccounts
    entityWorker
    entityBffPlan
    entityApiLayer
    entityOcr
    entityManagementLayer
    entityBff
    entityDataLayer
    entityOcrPlan
    entityWorkerPlan
    entityProcessingLayer
    entityKeyVault
    entityServiceBus
    entityCosmos
    entityKeepAliveFunc
    entitySubmitExpenses
    entityExpenseFlowApplication
  ]
}

resource relationshipStorageAccountsToSecondaryStorage 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  parent: healthModel
  name: '063cfc66-b335-41b2-a983-27d31c1978c1-f2a40f5e-52b2-48a2-96ce-33f4d884825d'
  properties: {
    childEntityName: 'f2a40f5e-52b2-48a2-96ce-33f4d884825d'
    parentEntityName: '063cfc66-b335-41b2-a983-27d31c1978c1'
  }
  dependsOn: [
    entitySecondaryStorage
    entityStorageAccounts
    entityWorker
    entityBffPlan
    entityApiLayer
    entityOcr
    entityManagementLayer
    entityBff
    entityDataLayer
    entityOcrPlan
    entityWorkerPlan
    entityProcessingLayer
    entityKeyVault
    entityServiceBus
    entityCosmos
    entityKeepAliveFunc
    entitySubmitExpenses
    entityExpenseFlowApplication
  ]
}

resource relationshipDataLayerToCosmos 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  parent: healthModel
  name: '839e8a4f-5b08-467c-aed8-56bd07f72db1-e69e768b-0355-49c6-9451-b94ced3046c8'
  properties: {
    childEntityName: 'e69e768b-0355-49c6-9451-b94ced3046c8'
    parentEntityName: '839e8a4f-5b08-467c-aed8-56bd07f72db1'
  }
  dependsOn: [
    entityPrimaryStorage
    entityWorker
    entityBffPlan
    entityApiLayer
    entityOcr
    entityManagementLayer
    entityBff
    entityDataLayer
    entityOcrPlan
    entityWorkerPlan
    entityProcessingLayer
    entityKeyVault
    entityServiceBus
    entityCosmos
    entityKeepAliveFunc
    entitySubmitExpenses
    entityExpenseFlowApplication
  ]
}

resource relationshipExpenseFlowApplicationToSubmitExpenses 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  parent: healthModel
  name: 'baa13677-d203-46f1-8b32-3075bdb68fc2'
  properties: {
    childEntityName: 'fc3e84a3-7c3a-4aff-b148-e764d3c71276'
    parentEntityName: healthModelName
  }
  dependsOn: [
    entityPrimaryStorage
    entityWorker
    entityBffPlan
    entityApiLayer
    entityOcr
    entityManagementLayer
    entityBff
    entityDataLayer
    entityOcrPlan
    entityWorkerPlan
    entityProcessingLayer
    entityKeyVault
    entityServiceBus
    entityCosmos
    entityKeepAliveFunc
    entitySubmitExpenses
    entityExpenseFlowApplication
  ]
}

resource relationshipProcessingLayerToWorker 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  parent: healthModel
  name: 'ccae2486-2116-4734-adc0-7c238458b6fb-0beddc06-19ae-4061-b104-0152c3e5dd8d'
  properties: {
    childEntityName: '0beddc06-19ae-4061-b104-0152c3e5dd8d'
    parentEntityName: 'ccae2486-2116-4734-adc0-7c238458b6fb'
  }
  dependsOn: [
    entityPrimaryStorage
    entityWorker
    entityBffPlan
    entityApiLayer
    entityOcr
    entityManagementLayer
    entityBff
    entityDataLayer
    entityOcrPlan
    entityWorkerPlan
    entityProcessingLayer
    entityKeyVault
    entityServiceBus
    entityCosmos
    entityKeepAliveFunc
    entitySubmitExpenses
    entityExpenseFlowApplication
  ]
}

resource relationshipProcessingLayerToKeyVault 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  parent: healthModel
  name: 'cd8497f5-688e-40a9-92d4-b308896c63bd'
  properties: {
    childEntityName: 'cd59fe0e-0ccf-4471-959b-9995cec4f206'
    parentEntityName: 'ccae2486-2116-4734-adc0-7c238458b6fb'
  }
  dependsOn: [
    entityPrimaryStorage
    entityWorker
    entityBffPlan
    entityApiLayer
    entityOcr
    entityManagementLayer
    entityBff
    entityDataLayer
    entityOcrPlan
    entityWorkerPlan
    entityProcessingLayer
    entityKeyVault
    entityServiceBus
    entityCosmos
    entityKeepAliveFunc
    entitySubmitExpenses
    entityExpenseFlowApplication
  ]
}

resource relationshipProcessingLayerToOcr 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  parent: healthModel
  name: 'd41eb4e7-736d-4b3b-b2c6-4e6380644bee'
  properties: {
    childEntityName: '63733205-1535-44ff-8962-6bad4e0aa0ee'
    parentEntityName: 'ccae2486-2116-4734-adc0-7c238458b6fb'
  }
  dependsOn: [
    entityPrimaryStorage
    entityWorker
    entityBffPlan
    entityApiLayer
    entityOcr
    entityManagementLayer
    entityBff
    entityDataLayer
    entityOcrPlan
    entityWorkerPlan
    entityProcessingLayer
    entityKeyVault
    entityServiceBus
    entityCosmos
    entityKeepAliveFunc
    entitySubmitExpenses
    entityExpenseFlowApplication
  ]
}

output healthModelResourceId string = healthModel.id
output healthModelPrincipalId string = healthModel.identity.principalId
output bffDeploymentAnnotationEntityNames array = [
  entityBff.name
  entityKeepAliveFunc.name
]
output workerDeploymentAnnotationEntityNames array = [
  entityWorker.name
]
output ocrDeploymentAnnotationEntityNames array = [
  entityOcr.name
]
