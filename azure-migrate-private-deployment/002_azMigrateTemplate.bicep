@description('Specifies a name for creating the migrate project.')
@maxLength(13)
param migrateProjectName string

@description('appliance name for the migrate project')
param applianceName string = 'appliance01'

@description('Specifies the resource id to the subnet, where pe should be deployed.')
param subnetId string

@description('Specifies the location of the subnet, where pe should be deployed.')
param subnetLocation string

@description('Should private endpoints be deployed?')
param deployPrivateEndpoints bool = false

@description('Specifies the object id of the admin user.')
param adminUserObjectId string = '7c9e2032-2321-416d-b206-bcab27c667ec'

@description('Specifies the recovery service name for the migrate project.')
param siteRecoveryName string = uniqueString('bck', resourceGroup().id)

@description('Specifies the key vault name for  the migrate project.')
param keyVaultName string = uniqueString('kv', resourceGroup().id)

@description('dns zone name id for private zone for storage blob')
param privateDnsBlobZoneNameId string = ''

@description('dns zone name id for private dns zone for storage queue')
param privateDnsQueueZoneNameId string = ''

@description('dns zone name id for private dns zone for site recovery vault')
param privateDnsSiteRecoveryZoneNameId string = ''

@description('dns zone name id for private dns zone for key vault')
param privateDnsVaultZoneNameId string = ''

@description('dns zone name id for private dns zone for azure migrate')
param privateDnsMigrateZoneNameId string = ''

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



// --------------------------------------------
// Creating a key vault for the migrate project
// --------------------------------------------
resource keyvault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: {
    'Migrate Project': migrateProjectName
  }
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enabledForDeployment: true
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    publicNetworkAccess: 'Disabled'
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: adminUserObjectId
        permissions: {
          keys: [
            'all'
          ]
          secrets: [
            'all'
          ]
          certificates: [
            'all'
          ]
          storage: [
            'all'
          ]
        }
      }
      {
        tenantId: subscription().tenantId
        objectId: migrateProject.identity.principalId
        permissions: {
          keys: [
            'all'
          ]
          secrets: [
            'all'
          ]
          certificates: [
            'all'
          ]
          storage: [
            'all'
          ]
        }
      }
    ]
  }
}

resource keyvault_pe 'Microsoft.Network/privateEndpoints@2020-05-01' = if (deployPrivateEndpoints) {
  name: '${keyVaultName}kvpe'
  properties: {
    privateLinkServiceConnections: [
      {
        name: '${keyVaultName}kvpe'
        properties: {
          privateLinkServiceId: keyvault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
    subnet: {
      id: subnetId
    }
  }
  location: subnetLocation
  tags: {
    MigrateProject: migrateProjectName
  }
}

resource keyvault_dnsz 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-05-01' = if (deployPrivateEndpoints) {
  name: '${keyVaultName}kvdnszg'
  parent: keyvault_pe
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink.vaultcore.azure.net'
        properties: {
          privateDnsZoneId: privateDnsVaultZoneNameId
        }
      }
    ]
  }
}

// ------------------------------------------------------
// Creating a site recovery vault for the migrate project
// ------------------------------------------------------
resource backup 'Microsoft.RecoveryServices/vaults@2024-10-01' = {
  name: siteRecoveryName
  location: location
  tags: {
    'Migrate Project': migrateProjectName
  }
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Disabled'
    securitySettings: {
      immutabilitySettings: {
        state: 'Disabled'
      }
    }
  }
}

resource backup_pe 'Microsoft.Network/privateEndpoints@2020-05-01' = if (deployPrivateEndpoints) {
  name: '${siteRecoveryName}rspe'
  properties: {
    privateLinkServiceConnections: [
      {
        name: '${siteRecoveryName}rspe'
        properties: {
          privateLinkServiceId: backup.id
          groupIds: [
            'AzureBackup'
          ]
        }
      }
    ]
    subnet: {
      id: subnetId
    }
  }
  location: subnetLocation
  tags: {
    MigrateProject: migrateProjectName
  }
}

resource backup_dnsz 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-05-01' = if (deployPrivateEndpoints) {
  name: '${siteRecoveryName}rsdnszg'
  parent: backup_pe
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink.${backcode}.backup.windowsazure.com'
        properties: {
          privateDnsZoneId: privateDnsSiteRecoveryZoneNameId
        }
      }
      {
        name: 'privatelink.queue.${environment().suffixes.storage}'
        properties: {
          privateDnsZoneId: privateDnsQueueZoneNameId
        }
      }
      {
        name: 'privatelink.blob.${environment().suffixes.storage}'
        properties: {
          privateDnsZoneId: privateDnsBlobZoneNameId
        }
      }
    ]
  }
}

module blobDnsDeployment '002_0_pre_creation.bicep' = if (deployPrivateEndpoints) {
  scope: resourceGroup(split(privateDnsBlobZoneNameId, '/')[2], split(privateDnsBlobZoneNameId, '/')[4])
  name: 'blobRecords'
  params: {
    nicId: backup_pe.properties.networkInterfaces[0].id
    privateDnsZoneName: 'privatelink.blob.${environment().suffixes.storage}'
  }
}

module queueDnsDeplyoment '002_0_pre_creation.bicep' = if (deployPrivateEndpoints) {
  scope: resourceGroup(split(privateDnsBlobZoneNameId, '/')[2], split(privateDnsBlobZoneNameId, '/')[4])
  name: 'queueRecords'
  params: {
    nicId: backup_pe.properties.networkInterfaces[0].id
    privateDnsZoneName: 'privatelink.queue.${environment().suffixes.storage}'
  }
}


// ---------------------------------------------------------
// Creating a migrate project & site for the migrate project
// ---------------------------------------------------------

resource migrateProject 'Microsoft.Migrate/migrateProjects@2020-05-01' = {
  name: migrateProjectName
  location: location
  tags: {
    'Migrate Project': migrateProjectName
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Disabled'
  }
}

resource migrateProject_Servers_Assessment_ServerAssessment 'Microsoft.Migrate/migrateProjects/solutions@2020-05-01' = {
  parent: migrateProject
  name: 'Servers-Assessment-ServerAssessment'
  properties: {
    tool: 'ServerAssessment'
    purpose: 'Assessment'
    goal: 'Servers'
    status: 'Active'
  }
}

resource migrateProject_Servers_Discovery_ServerDiscovery 'Microsoft.Migrate/migrateProjects/solutions@2020-05-01' = {
  parent: migrateProject
  name: 'Servers-Discovery-ServerDiscovery'
  properties: {
    tool: 'ServerDiscovery'
    purpose: 'Discovery'
    goal: 'Servers'
    status: 'Inactive'
    details: {
      extendedDetails: {
        privateEndpointDetails: '{"subnetId":"${subnetId}","virtualNetworkLocation":"${subnetLocation}","skipPrivateDnsZoneCreation":false}'
      }
    }
  }
}

resource migrateProject_Servers_Migration_ServerMigration 'Microsoft.Migrate/migrateProjects/solutions@2020-05-01' = {
  parent: migrateProject
  name: 'Servers-Migration-ServerMigration'
  properties: {
    tool: 'ServerMigration'
    purpose: 'Migration'
    goal: 'Servers'
    status: 'Active'
  }
}

resource migrateProject_pe 'Microsoft.Network/privateEndpoints@2020-05-01' = if (deployPrivateEndpoints) {
  name: '${migrateProjectName}pe'
  properties: {
    privateLinkServiceConnections: [
      {
        name: '${migrateProjectName}pe'
        properties: {
          privateLinkServiceId: migrateProject.id
          groupIds: [
            'Default'
          ]
        }
      }
    ]
    subnet: {
      id: subnetId
    }
  }
  location: subnetLocation
  tags: {
    MigrateProject: migrateProjectName
  }
}

resource migrateProject_dnsz 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-05-01' = if (deployPrivateEndpoints) {
  name: '${migrateProjectName}dnszg'
  parent: migrateProject_pe
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink.prod.migration.windowsazure.com'
        properties: {
          privateDnsZoneId: privateDnsMigrateZoneNameId
        }
      }
    ]
  }
}


resource migrateSite 'Microsoft.OffAzure/vmwareSites@2023-06-06' = {
  name: '${migrateProjectName}site'
  location: location
  tags: {
    'Migrate Project': migrateProjectName
  }
  properties: {
    agentDetails: {
      keyVaultId: keyvault.id
      keyVaultUri: keyvault.properties.vaultUri
    }
    applianceName: applianceName
    discoverySolutionId: migrateProject_Servers_Discovery_ServerDiscovery.id
  }
}

resource migrateAssessmentProject 'Microsoft.Migrate/assessmentProjects@2023-03-15' = {
  name: '${migrateProjectName}project'
  location: location
  tags: {
    'Migrate Project': migrateProjectName
  }
  properties: {
    projectStatus: 'Active'
    assessmentSolutionId: migrateProject_Servers_Assessment_ServerAssessment.id
  }
}

resource migrateMasterSite 'Microsoft.OffAzure/masterSites@2023-06-06' = {
  name: '${migrateProjectName}mastersite'
  location: location
  tags: {
    'Migrate Project': migrateProjectName
  }
  properties: {
    sites: [
      migrateSite.id
    ]
    allowMultipleSites: true
  }
}


resource migrateMasterSite_sqlsites  'Microsoft.OffAzure/masterSites/sqlSites@2023-06-06' = {
  parent: migrateMasterSite
  name: '${migrateProjectName}sqlsites'
  properties: {
    discoverySolutionId: migrateProject_Servers_Discovery_ServerDiscovery.id
    siteAppliancePropertiesCollection: [
      {
        agentDetails: {
          keyVaultId: keyvault.id
          keyVaultUri: keyvault.properties.vaultUri
        }
        applianceName: applianceName
      }
    ]
  }
}

resource migrateMasterSite_webappsites 'Microsoft.OffAzure/masterSites/webAppSites@2023-06-06' = {
  parent: migrateMasterSite
  name: '${migrateProjectName}webappsites'
  properties: {
    discoverySolutionId: migrateProject_Servers_Discovery_ServerDiscovery.id
    siteAppliancePropertiesCollection: [
      {
        agentDetails: {
          keyVaultId: keyvault.id
          keyVaultUri: keyvault.properties.vaultUri
        }
        applianceName: applianceName
      }
    ]
  }
}




output projecturl string = reference(migrateProject.id, '2020-05-01', 'Full').properties.serviceEndpoint
