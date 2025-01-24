param(
    [string] $resourceGroupName = "adffunc",
    [string] $location = "northeurope"
)


# check if resour

$resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
if(-not $resourceGroup) {
    Write-Host "Creating resource group $resourceGroupName in location $location"
    New-AzResourceGroup -Name $resourceGroupName -Location $location
}

# run deployment
$params = @{
    "location" = $location
}
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile .\template.bicep -Name adffunc-deploy @params

