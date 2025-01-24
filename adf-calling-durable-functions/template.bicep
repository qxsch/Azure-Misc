param datafactory_name string = 'adf${uniqueString(resourceGroup().id)}'
param function_name string = 'fa${uniqueString(resourceGroup().id)}'
param storage_account_name string = 'st${uniqueString(resourceGroup().id)}'
param app_service_plan_name string = 'asp${uniqueString(resourceGroup().id)}'

@allowed([ 'eastus', 'eastus2', 'westus', 'westus2', 'centralus', 'northcentralus', 'southcentralus', 'northeurope', 'westeurope', 'eastasia', 'southeastasia', 'japaneast', 'japanwest', 'australiaeast', 'australiasoutheast', 'australiacentral', 'australiacentral2', 'brazilsouth', 'southindia', 'centralindia', 'westindia', 'canadacentral', 'canadaeast', 'uksouth', 'ukwest', 'koreacentral', 'koreasouth', 'francecentral', 'francesouth', 'germanywestcentral', 'norwayeast', 'switzerlandnorth', 'uaenorth', 'southafricanorth', 'southafricawest', 'eastus2euap', 'westcentralus', 'westus3', 'southeastasia2', 'brazilsoutheast', 'australiacentral', 'australiacentral2', 'australiasoutheast', 'japaneast', 'japanwest', 'koreacentral', 'koreasouth', 'southindia', 'centralindia', 'westindia', 'canadacentral', 'canadaeast', 'uksouth', 'ukwest', 'francecentral', 'northeurope', 'norwayeast', 'switzerlandnorth', 'germanywestcentral', 'westeurope', 'eastus2euap', 'westcentralus', 'westus3', 'southafricanorth', 'southafricawest', 'uaenorth', 'eastasia', 'southeastasia', 'centralus', 'eastus', 'eastus2', 'northcentralus', 'southcentralus', 'westus', 'westus2' ])
param location string


// -----------------------------------
// Function App (with Storage Account)
// -----------------------------------

resource storage_resource 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storage_account_name
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'Storage'
  properties: {
    allowBlobPublicAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
    }
  }
}

resource storage_blob 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage_resource
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      allowPermanentDelete: false
      enabled: false
    }
  }
}

resource storage_queue 'Microsoft.Storage/storageAccounts/queueServices@2023-05-01' = {
  parent: storage_resource
  name: 'default'
}

resource storage_table 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storage_resource
  name: 'default'
}

resource storage_files 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: storage_resource
  name: 'default'
  properties: {
    protocolSettings: {
      smb: {}
    }
    cors: {
      corsRules: []
    }
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}



resource asp_resource 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: app_service_plan_name
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  kind: 'functionapp'
  properties: {
    perSiteScaling: false
    elasticScaleEnabled: false
    maximumElasticWorkerCount: 1
    isSpot: false
    reserved: false
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
    zoneRedundant: false
  }
}

resource function_resource 'Microsoft.Web/sites@2024-04-01' = {
  name: function_name
  location: location
  kind: 'functionapp'
  properties: {
    enabled: true
    serverFarmId: asp_resource.id
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: 'v6.0'
      powerShellVersion: '7.2'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storage_resource.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storage_resource.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storage_resource.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storage_resource.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: 'contentshare' // storage_files_contentshare.name
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
        supportCredentials: false
      }
      ipSecurityRestrictions: [
        {
          ipAddress: 'Any'
          action: 'Allow'
          priority: 2147483647
          name: 'Allow all'
          description: 'Allow all access'
        }
      ]
      scmIpSecurityRestrictions: [
        {
          ipAddress: 'Any'
          action: 'Allow'
          priority: 2147483647
          name: 'Allow all'
          description: 'Allow all access'
        }
      ]
    }
  }
  dependsOn: [
    storage_blob
    storage_queue
    storage_table
  ]
}

resource function_DurableFunctionsHttpStart 'Microsoft.Web/sites/functions@2024-04-01' = {
  parent: function_resource
  name: 'DurableFunctionsHttpStart'
  properties: {
    files: {
        'function.json': loadTextContent('azfunc/DurableFunctionsHttpStart/function.json')
        'run.ps1': loadTextContent('azfunc/DurableFunctionsHttpStart/run.ps1')
    }
    language: 'powershell'
  }
}

resource function_DurableFunctionsOrchestrator 'Microsoft.Web/sites/functions@2024-04-01' = {
  parent: function_resource
  name: 'DurableFunctionsOrchestrator'
  properties: {
    files: {
        'function.json': loadTextContent('azfunc/DurableFunctionsOrchestrator/function.json')
        'run.ps1': loadTextContent('azfunc/DurableFunctionsOrchestrator/run.ps1')
    }
    language: 'powershell'
  }
}

resource function_HelloActivity 'Microsoft.Web/sites/functions@2024-04-01' = {
  parent: function_resource
  name: 'HelloActivity'
  properties: {
    files: {
        'function.json': loadTextContent('azfunc/HelloActivity/function.json')
        'run.ps1': loadTextContent('azfunc/HelloActivity/run.ps1')
    }
    language: 'powershell'
  }
}

resource function_SyncHttp 'Microsoft.Web/sites/functions@2024-04-01' = {
  parent: function_resource
  name: 'SyncHttp'
  properties: {
    files: {
        'function.json': loadTextContent('azfunc/SyncHttp/function.json')
        'run.ps1': loadTextContent('azfunc/SyncHttp/run.ps1')
    }
    language: 'powershell'
  }
}

// -----------------------------------
// Data Factory
// -----------------------------------

resource adf_resource 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: datafactory_name
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

resource adf_managed_vnet 'Microsoft.DataFactory/factories/managedVirtualNetworks@2018-06-01' = {
  parent: adf_resource
  name: 'default'
  properties: {}
}

resource adf_AutoResolveIntegrationRuntime 'Microsoft.DataFactory/factories/integrationRuntimes@2018-06-01' = {
  parent: adf_resource
  name: 'AutoResolveIntegrationRuntime'
  properties: {
    type: 'Managed'
    managedVirtualNetwork: {
      referenceName: 'default'
      type: 'ManagedVirtualNetworkReference'
    }
    typeProperties: {
      computeProperties: {
        location: 'AutoResolve'
        dataFlowProperties: {
          computeType: 'General'
          coreCount: 8
          timeToLive: 0
        }
      }
    }
  }
  dependsOn: [
    adf_managed_vnet
  ]
}

resource adf_AzureBlobStorageLinkedService 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: adf_resource
  name: 'AzureFunctionApp'
  properties: {
    type: 'AzureFunction'
    typeProperties: {
      functionAppUrl: 'https://${function_resource.properties.defaultHostName}'
      authentication: 'Anonymous'
    }
  }
}

resource adf_pipeline_DurabaleFuncCaller 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  parent: adf_resource
  name: 'DurabaleFuncCaller'
  properties: loadJsonContent('adf/durableFuncCallerPipeline.json').properties
  dependsOn: [
    adf_AzureBlobStorageLinkedService
  ]
}

resource adf_pipeline_TestPipe 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  parent: adf_resource
  name: 'TestPipe'
  properties: loadJsonContent('adf/TestPipeLine.json').properties
  dependsOn: [
    adf_AzureBlobStorageLinkedService
    adf_pipeline_DurabaleFuncCaller
  ]
}
