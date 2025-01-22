param(   
    [Parameter(Position=0, mandatory=$true)]
    [string]$migrateProjectName,
    [Parameter(Position=1, mandatory=$false)]
    [string]$applianceName = "",
    [Parameter(Position=2, mandatory=$false)]
    [string]$siteRecoveryName="",
    [Parameter(Position=3, mandatory=$false)]
    [string]$keyVaultName= "",
    [Parameter(Position=4, mandatory=$false)]
    [string]$adminUserObjectId="",

    [string]$vnetName = "vnet",
    [string]$vnetPrefix = "10.0.0.0/23",
    [string]$subnetName = "default",
    [string]$subnetPrefix = "10.0.0.0/24",
    [string]$vnetId = "",

    [string]$resourceGroupName = "azmigrate",
    [string]$location = "northeurope"
)


if($migrateProjectName.Trim() -eq "") {
    throw "migrateProjectName is required"
}


if($adminUserObjectId.Trim() -eq "") {
    $adminUserObjectId = ((Get-AzContext).Account.ExtendedProperties['HomeAccountId'] -split '\.')[0]
    Write-Host "Using current user as the admin user: $adminUserObjectId"
}


# Create a new resource group in case it does not exist
$resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
if (-not $resourceGroup) {
    Write-Host "Creating resource group $resourceGroupName in location $location"
    New-AzResourceGroup -Name $resourceGroupName -Location $location
}


# Deploy the ARM template
Write-Host "Deploying Template 001_azRequirements.bicep"
$params  = @{
    ResourceGroupName = $resourceGroupName
    Location = $location
    vnetName = $vnetName
    vnetPrefix = $vnetPrefix
    subnetName = $subnetName
    subnetPrefix = $subnetPrefix
    deployVnet = ($vnetId.Trim() -eq "")
}
$result = New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile .\001_azRequirements.bicep -Name "001_azRequirements"  @params -ErrorAction Stop

$result


# setting vnetId if it was not provided
if($result.Outputs.vnetId -and $result.Outputs.vnetId.Value -and  $vnetId.Trim() -eq "") {
    $vnetId = $result.Outputs.vnetId.Value
    $vnetLocation = $location
}
else {
    $vnetLocation = (Get-AzResource -ResourceId $vnetId -ErrorAction Stop).Location
}
$subnetId = $vnetId + "/subnets/" + $subnetName
# setting other ids
if(
    $result.Outputs.privateDnsBlobZoneNameId -and $result.Outputs.privateDnsBlobZoneNameId.Value -and 
    $result.Outputs.privateDnsQueueZoneNameId -and $result.Outputs.privateDnsQueueZoneNameId.Value -and
    $result.Outputs.privateDnsSiteRecoveryZoneNameId -and $result.Outputs.privateDnsSiteRecoveryZoneNameId.Value -and
    $result.Outputs.privateDnsVaultZoneNameId -and $result.Outputs.privateDnsVaultZoneNameId.Value -and 
    $result.Outputs.privateDnsMigrateZoneNameId -and $result.Outputs.privateDnsMigrateZoneNameId.Value
) {
    $blobZoneId = $result.Outputs.privateDnsBlobZoneNameId.Value
    $queueZoneId = $result.Outputs.privateDnsQueueZoneNameId.Value
    $siteRecoveryZoneId = $result.Outputs.privateDnsSiteRecoveryZoneNameId.Value
    $vaultZoneId = $result.Outputs.privateDnsVaultZoneNameId.Value
    $migrateZoneId = $result.Outputs.privateDnsMigrateZoneNameId.Value
}
else {
    throw "Private DNS zones were not created (did not get the zone ids)"
}



Write-Host "Deploying Template 002_azMigrateTemplate.bicep"
$params  = @{
    ResourceGroupName = $resourceGroupName
    Location = $location
    subnetId = $subnetId
    subnetLocation = $vnetLocation

    adminUserObjectId = $adminUserObjectId
    migrateProjectName = $migrateProjectName
    privateDnsBlobZoneNameId = $blobZoneId
    privateDnsQueueZoneNameId = $queueZoneId
    privateDnsSiteRecoveryZoneNameId = $siteRecoveryZoneId
    privateDnsVaultZoneNameId = $vaultZoneId
    privateDnsMigrateZoneNameId = $migrateZoneId

}

if($applianceName.Trim() -ne "") {
    $params.Add("applianceName", $applianceName)
}
if($siteRecoveryName.Trim() -ne "") {
    $params.Add("siteRecoveryName", $siteRecoveryName)
}
if($keyVaultName.Trim() -ne "") {
    $params.Add("keyVaultName", $keyVaultName)
}

$result = New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile .\002_azMigrateTemplate.bicep -Name "002_azMigrateTemplate"  @params -ErrorAction Stop
$result
