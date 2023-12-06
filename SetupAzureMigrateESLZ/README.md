# Setup Azure Migrate within ESLZ

You have a landingzones (f.e. where private DNS zones live in one subscription, vnet lives in another subscription, etc.) and you want to setup Azure Migrate to assess your on-premises environment.

# Guide

1. Create the lab environment - __**optional, this is not required if you already have a landingzone setup**__
    1. Configure the setup.ps1 file 
        ```powershell
        # ----- BEGIN OF CONFIGURATION -----
        $subscriptionid      = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
        $resourcegroup       = 'RGNAMEHERE'
        $location            = 'eastus2'
        # ----- END OF CONFIGURATION -----
        ```

    1. Run the deploy.ps1 file
        ```powershell
        .\setup.ps1
        ```

1. Configure the deploy.ps1 file 
    ```powershell
    # ----- BEGIN OF CONFIGURATION -----
    $subscriptionid      = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
    $resourcegroup       = 'RGNAMEHERE'
    $migrateprojectname  = 'PROJECTNAMEHERE'
    $location            = 'westus2'

    $privatednszoneresourceid  = '/subscriptions/zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz/resourceGroups/RGNAMEHERE/providers/Microsoft.Network/privateDnsZones/privatelink.prod.migration.windowsazure.com'
    $subnetresourceid          = '/subscriptions/yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy/resourceGroups/RGNAMEHERE/providers/Microsoft.Network/virtualNetworks/VNETNAMEHERE/subnets/SUBNETNAMEHERE'
    # ----- END OF CONFIGURATION -----
    ```
1. Run the deploy.ps1 file
    ```powershell
    .\deploy.ps1
    ```

1. to clean up all the resources
    1. Configure the teardown.ps1 file  
        ```powershell
        # ----- BEGIN OF CONFIGURATION -----
        $subscriptionid      = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
        $resourcegroup       = 'RGNAMEHERE'
        # ----- END OF CONFIGURATION -----
        ```

    1. Run the deploy.ps1 file
        ```powershell
        .\teardown.ps1
        ```