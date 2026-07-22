@description('Azure region for the private endpoint.')
param location string

@description('Private endpoint name.')
param name string

@description('Subnet ID where the private endpoint is deployed.')
param subnetId string

@description('Resource ID of the private link target.')
param targetResourceId string

@description('Private link group IDs for the target resource.')
param groupIds array

@description('Private DNS zone ID associated with this endpoint.')
param privateDnsZoneId string

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
          privateLinkServiceId: targetResourceId
          groupIds: groupIds
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
      {
        name: 'default'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

output id string = privateEndpoint.id
