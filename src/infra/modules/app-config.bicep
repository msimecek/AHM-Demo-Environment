targetScope = 'resourceGroup'

@description('App Configuration store name.')
@minLength(5)
@maxLength(50)
param name string

@description('Azure region for the App Configuration store.')
param location string

@description('Tags applied to the App Configuration store.')
param tags object = {}

@description('SKU name for the App Configuration store.')
@allowed([
  'free'
  'developer'
  'standard'
  'premium'
])
param skuName string = 'free'

resource store 'Microsoft.AppConfiguration/configurationStores@2024-05-01' = {
  name: name
  location: location
  sku: {
    name: skuName
  }
  tags: tags
  properties: {}
}

output id string = store.id
output name string = store.name
