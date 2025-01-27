param(
    [string] $resourceGroupName = "durablefunc",
    [string] $location = "northeurope",

    [string]$functionName = '',
    [string]$storageAccountName = '',
    [string]$appServicePlanName = ''
)


$resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
if(-not $resourceGroup) {
    Write-Host "Creating resource group $resourceGroupName in location $location"
    New-AzResourceGroup -Name $resourceGroupName -Location $location
}

# run deployment
$params = @{
    "location" = $location
}
if($functionName.Trim() -ne '') {
    $params["function_name"] = $functionName
}
if($storageAccountName.Trim() -ne '') {
    $params["storage_account_name"] = $storageAccountName
}
if($appServicePlanName.Trim() -ne '') {
    $params["app_service_plan_name"] = $appServicePlanName
}
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile .\template.bicep -Name durablefunc @params
