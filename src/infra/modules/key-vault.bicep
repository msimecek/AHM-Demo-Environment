@description('Azure region for Key Vault.')
param location string

@description('Globally unique Key Vault name.')
@minLength(3)
@maxLength(24)
param name string

@description('Tags applied to Key Vault.')
param tags object

@description('When true, disables public network access.')
param restrictNetworkAccess bool = true

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    accessPolicies: []
    enablePurgeProtection: true
    enableRbacAuthorization: true
    enableSoftDelete: true
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    publicNetworkAccess: restrictNetworkAccess ? 'Disabled' : 'Enabled'
    softDeleteRetentionInDays: 7
    networkAcls: {
      bypass: 'None'
      defaultAction: restrictNetworkAccess ? 'Deny' : 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

output id string = vault.id
output name string = vault.name
output vaultUri string = vault.properties.vaultUri
