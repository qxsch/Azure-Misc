

param nicData object
param privateDnsZoneName string



// loop through the ip configurations
resource privateDnsRecords 'Microsoft.Network/privateDnsZones/A@2024-06-01' = [for ipConfig in nicData.properties.ipConfigurations : {
  name: '${privateDnsZoneName}/${split(ipConfig.properties.privateLinkConnectionProperties.fqdns[0], '.')[0]}'
  properties: {
    ttl: 60
    aRecords: [
      {
        ipv4Address: ipConfig.properties.privateIPAddress
      }
    ]
  }
}]




