# ----- BEGIN OF CONFIGURATION -----
$subscriptionid      = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
$resourcegroup       = 'RGNAMEHERE'
$location            = 'eastus2'
# ----- END OF CONFIGURATION -----


# select subscription
Select-AzSubscription -SubscriptionId $subscriptionid -Scope Process | Out-Null

# creating resource group
try {
    Get-AzResourceGroup -Name $resourcegroup -ErrorAction Stop | Out-Null
    Write-Host "Resource group $resourcegroup already exists"
}
catch {
    New-AzResourceGroup -Name $resourcegroup -Location $location -ErrorAction Stop
    Write-Host "Resource group $resourcegroup has been created"
}

# creating private dns zone
try {
    Get-AzPrivateDnsZone -ResourceGroupName $resourcegroup -Name 'privatelink.prod.migration.windowsazure.com' -ErrorAction Stop | Out-Null
    Write-Host "Private DNS Zone privatelink.prod.migration.windowsazure.com already exists"
}
catch {
    New-AzPrivateDnsZone -ResourceGroupName $resourcegroup -Name 'privatelink.prod.migration.windowsazure.com' -ErrorAction Stop
    Write-Host "Private DNS Zone privatelink.prod.migration.windowsazure.com has been created"
}

# creating vnet
try {
    Get-AzVirtualNetwork -ResourceGroupName $resourcegroup -Name 'testnet' -ErrorAction Stop | Out-Null
    Write-Host "VNet testnet already exists"
}
catch {
    $virtualNetwork = New-AzVirtualNetwork -ResourceGroupName $resourcegroup -Name 'testnet' -Location $location -AddressPrefix '10.0.0.0/16' -ErrorAction Stop
    Add-AzVirtualNetworkSubnetConfig  -Name 'default'-AddressPrefix '10.0.0.0/24' -VirtualNetwork $virtualNetwork  -ErrorAction Stop | Out-Null
    $virtualNetwork | Set-AzVirtualNetwork | Out-Null

    Write-Host "VNet testnet has been created"
}
