<#
.SYNOPSIS
    Retrieves VMware site information from Azure.

.DESCRIPTION
    This script retrieves VMware site information from Azure using the specified resource group name and subscription ID. If the subscription ID is not provided, it defaults to the current Azure context subscription ID.

.PARAMETER resourceGroupName
    The name of the resource group containing the VMware sites.

.PARAMETER subscriptionId
    The subscription ID for the Azure account. If not provided, the script uses the current Azure context subscription ID.

.EXAMPLE
    .\Get-VMwareSites.ps1 -resourceGroupName "MyResourceGroup"
    Retrieves VMware site information from the specified resource group using the current Azure context subscription ID.

.NOTES
    Requires the Az module and appropriate permissions to access the Azure resources.
#>
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$resourceGroupName = "",

    [string]$subscriptionId = ""
)

if($subscriptionId -eq "") {
    $subscriptionId = (Get-AzContext).Subscription.Id
}

$sites = (Invoke-AzRestMethod `
    -SubscriptionId $subscriptionId `
    -ResourceGroupName $resourceGroupName `
    -ResourceProviderName "Microsoft.OffAzure" `
    -ResourceType "VMwareSites" `
    -ApiVersion '2020-01-01' `
    -Method GET).Content | ConvertFrom-Json -Depth 100

if($null -ne $sites -and $sites.value -and $sites.value.Length -gt 0) {
    $sites.value | Select-Object -Property @{Name="siteName"; Expression={ $_.name}}, @{Name="location"; Expression={ $_.location}}, @{Name="applianceName"; Expression={ $_.properties.applianceName}}
}
else {
    Write-Host "No sites found"
}
