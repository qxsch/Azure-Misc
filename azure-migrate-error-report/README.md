# Migrate Error Reporting
Miscellaneous Azure stuff (includes demos for educational purposes only)


## How to use

1. Discover any VMWare Sites in a Resource Group
    ```pwsh
    ./getVmwareSites.ps1 -resourceGroupName "MyResourceGroup"
    ```
1. Export VMWare Site Errors
    ```pwsh
    ./exportVmwareErrors.ps1 -resourceGroupName "MyResourceGroup" -siteName "MySiteName"
    ```
1. Take a look at the exported errors in the `errors.csv` and `groupedErrors.csv` files
1. Optionally, you can also take a look at the `response.*.json` files
