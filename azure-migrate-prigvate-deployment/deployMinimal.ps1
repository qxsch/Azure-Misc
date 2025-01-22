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


    [Parameter(Position=5, mandatory=$true)]
    [string]$subnetId,
    [Parameter(Position=6, mandatory=$true)]
    [string]$blobZoneId,
    [Parameter(Position=7, mandatory=$true)]
    [string]$queueZoneId,
    [Parameter(Position=8, mandatory=$true)]
    [string]$siteRecoveryZoneId,
    [Parameter(Position=9, mandatory=$true)]
    [string]$vaultZoneId,
    [Parameter(Position=10, mandatory=$true)]
    [string]$migrateZoneId,

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


$vnetLocation = (Get-AzResource -ResourceId $subnetId -ErrorAction Stop).Location


Write-Host "Deploying Template 002_azMigrateTemplate.bicep"
$params  = @{
    ResourceGroupName = $resourceGroupName
    Location = $location
    subnetId = $subnetId
    subnetLocation = $vnetLocation

    adminUserObjectId = $adminUserObjectId
    migrateProjectName = $migrateProjectName
    siteRecoveryName = $siteRecoveryName
    kevVaultName = $keyVaultName
    privateDnsBlobZoneNameId = $blobZoneId
    privateDnsQueueZoneNameId = $queueZoneId
    privateDnsSiteRecoveryZoneNameId = $siteRecoveryZoneId
    privateDnsVaultZoneNameId = $vaultZoneId
    privateDnsMigrateZoneNameId = $migrateZoneId

}
$result = New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile .\002_azMigrateTemplate.bicep -Name "002_azMigrateTemplate"  @params -ErrorAction Stop
$result
