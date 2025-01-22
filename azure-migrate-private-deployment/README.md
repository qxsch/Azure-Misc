# Azure Migrate Custom Deployment
*Goal:* Deploy Azure Migrate and setup a VMWare Appliances

## Setup

1. Run the Azure Migrate Deployment there are 3 flavors:
   ```pwsh
   # Option A: deploy everything
   .\deployFull.ps1 -migrateProjectName "vmwaremigration" -applianceName "myappliance"
   
   # Option B: use this in case you already have a vnet (will just deploy Private DNS Zones and link them to the vnet)
   $params = @{
        migrateProjectName = "vmwaremigration"
        applianceName = "myappliance"
        vnetId = "/subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.Network/virtualNetworks/<vnetName>"
        subnetName = "default"
   }
   .\deployFull.ps1 @params

   # Option C: use this in case you already have a vnet and a private DNS Zone (will just use them)
   $params = @{
        migrateProjectName = "vmwaremigration"
        applianceName = "myappliance"
        subnetId = "/subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.Network/virtualNetworks/<vnetName>/subnets/<subnetName>"
        blobZoneId = "/subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
        queueZoneId = "/subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"
        siteRecoveryZoneId = "/subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.Network/privateDnsZones/privatelink.<regioncode>.backup.windowsazure.com"
        vaultZoneId = "/subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
        migrateZoneId = "/subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.Network/privateDnsZones/privatelink.prod.migration.windowsazure.com"
   }
   .\deployFull.ps1 @params
   ```

