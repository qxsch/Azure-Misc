

param nicId string
param privateDnsZoneName string


var nicData = reference(nicId, '2024-05-01', 'Full')

module queueDnsDeplyoment '002_0_0_createdns.bicep' = {
  scope: resourceGroup()
  name: '${deployment().name}-a-record'
  params: {
    nicData: nicData
    privateDnsZoneName: privateDnsZoneName
  }
}


//output fqdn1 string = split(reference(nicId, '2024-05-01', 'Full').properties.ipConfigurations[0].properties.privateLinkConnectionProperties.fqdns[0], '.')[0]
//output fqdn2 string = split(reference(nicId, '2024-05-01', 'Full').properties.ipConfigurations[1].properties.privateLinkConnectionProperties.fqdns[0], '.')[0]
