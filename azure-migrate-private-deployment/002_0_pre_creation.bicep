

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



