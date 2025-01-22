@description('Specifies the location for all resources.')
@allowed([
  'centralus'
  'eastasia'
  'northeurope'
  'westeurope'
  'westus2'
  'australiasoutheast'
  'uksouth'
  'ukwest'
  'canadacentral'
  'centralindia'
  'southindia'
  'japaneast'
  'japanwest'
  'brazilsouth'
  'koreasouth'
  'koreacentral'
  'francecentral'
  'switzerlandnorth'
  'australiaeast'
  'southeastasia'
  'centraluseuap'
  'eastus2euap'
  'canadaeast'
  'southcentralus'
])
param location string

param vnetname string = 'vnet'
param vnetPrefix string = '10.0.0.0/23'
param subnetname string = 'default'
param subnetPrefix string = '10.0.0.0/24'
param deployVnet bool = true


var backupLookup = {
  centralus : 'cus'
  eastasia : 'ea'
  northeurope : 'ne'
  westeurope : 'we'
  westus2 : 'wus2'
  australiasoutheast : 'ase'
  uksouth : 'uks'
  ukwest : 'ukw'
  canadacentral : 'cnc'
  centralindia : 'inc'
  southindia : 'ins'
  japaneast : 'jpe'
  japanwest : 'jpw'
  brazilsouth : 'brs'
  koreasouth : 'krs'
  koreacentral : 'krc'
  francecentral : 'frc'
  switzerlandnorth : 'szn'
  australiaeast : 'ae'
  southeastasia : 'sea'
  centraluseuap : 'ccy'
  eastus2euap : 'ecy'
  canadaeast : 'cne'
  southcentralus : 'scus'
}
var backcode = backupLookup[location]

// create vnet and subnet
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = if (deployVnet) {
  name: vnetname
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetPrefix
      ]
    }
    subnets: [
      {
        name: subnetname
        properties: {
          addressPrefix: subnetPrefix
        }
      }
    ]
  }
}


// create private dns zone for storage account (blob) and link to vnet (required by recovery services vault)
resource privateDnsBlobZone 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'

}
resource privateDnsBlobLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  name: 'link-blob-storage'
  parent: privateDnsBlobZone
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}


// create private dns zone for storage account (queue) and link to vnet (required by recovery services vault)
resource privateDnsQueueZone 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: 'privatelink.queue.${environment().suffixes.storage}'
  location: 'global'

}
resource privateDnsQueueLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  name: 'link-queue-storage'
  parent: privateDnsQueueZone
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}


// create private dns zone for recovery services vault and link to vnet (required by recovery services vault)
resource privateDnsSiteRecoveryZone 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: 'privatelink.${backcode}.backup.windowsazure.com'
  location: 'global'
}
resource privateDnsSiteRecoveryLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  name: 'link-site-recovery'
  parent: privateDnsSiteRecoveryZone
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}


// create private dns zone for key vault and link to vnet
resource privateDnsVaultZone 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
}
resource privateDnsVaultLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  name: 'link-keyvault'
  parent: privateDnsVaultZone
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}


// create the azure migrate dns zone and link to vnet
resource privateDnsMigrateZone 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: 'privatelink.prod.migration.windowsazure.com'
  location: 'global'
}
resource privateDnsMigrateLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  name: 'link-migrate'
  parent: privateDnsMigrateZone
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}


output vnetId string = deployVnet ? vnet.id : ''
output privateDnsBlobZoneNameId string = privateDnsBlobZone.id
output privateDnsQueueZoneNameId string = privateDnsQueueZone.id
output privateDnsSiteRecoveryZoneNameId string = privateDnsSiteRecoveryZone.id
output privateDnsVaultZoneNameId string = privateDnsVaultZone.id
output privateDnsMigrateZoneNameId string = privateDnsMigrateZone.id

