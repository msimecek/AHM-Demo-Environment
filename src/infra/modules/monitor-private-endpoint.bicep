@description('Azure region for the private endpoint.')
param location string

@description('Private endpoint name.')
param name string

@description('Subnet ID where the private endpoint is deployed.')
param subnetId string

@description('Azure Monitor Private Link Scope resource ID.')
param privateLinkScopeId string

@description('Private DNS zone IDs associated with Azure Monitor private link.')
param privateDnsZoneIds array

@description('Tags applied to the private endpoint.')
param tags object

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${name}-connection'
        properties: {
          privateLinkServiceId: privateLinkScopeId
          groupIds: [
            'azuremonitor'
          ]
        }
      }
    ]
  }
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      for (privateDnsZoneId, index) in privateDnsZoneIds: {
        name: 'zone-${index}'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

output id string = privateEndpoint.id
