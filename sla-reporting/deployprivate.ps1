param(
    [Parameter(Mandatory=$true)]
    [string] $slareportingrg,


    [string] $workspaceName = "sadnj32njsafglaw",
    [int]    $workspaceSlaTableRetentionINDays = 30,
    [string] $dataCollectionRuleName = "sadnj32njsafgrule",
    [string] $dataCollectionEndpointName = "sadnj32njsafgep",
    [string] $functionAppName = "sadnj32njsafg",
    [string] $storageAccountName = "sadnj32njsafg",
    [string] $hostingPlanName = "sadnj32njsafgplan",
    [string] $hostingPlanSku = "Premium0V3",
    [string] $hostingPlanSkuCode = "P0V3",
    [int]    $hostingPlanWorkerCount =  1,
    [bool]   $hostingPlanZoneRedundant = $false,
    [string] $deplyomentFeatures = "full",


    [string]$networkingrg = "",
    [string]$vnetFuncSubnetResourceId = "",
    [string]$vnetPrivateEndpointSubnetResourceId = "",
    [string]$privateStorageBlobDnsZoneResourceId = "",
    [string]$privateStorageQueueDnsZoneResourceId = "",
    [string]$privateStorageTableDnsZoneResourceId = ""
)


# optional baseline networking resources deployment
if( $networkingrg -ne "" ) {
    Write-Host -ForegroundColor Green "Deploying networking resources to $networkingrg"
    $result = New-AzResourceGroupDeployment -ResourceGroupName $networkingrg -TemplateFile .\tmpls\private\privatenetworking-template.json
    # $result.Outputs.vnetResourceId.Value
    $vnetFuncSubnetResourceId              = $result.Outputs.vnetFuncSubnetResourceId.Value
    $vnetPrivateEndpointSubnetResourceId   = $result.Outputs.vnetPrivateEndpointSubnetResourceId.Value
    $privateStorageBlobDnsZoneResourceId   = $result.Outputs.privateStorageBlobDnsZoneResourceId.Value
    $privateStorageQueueDnsZoneResourceId  = $result.Outputs.privateStorageQueueDnsZoneResourceId.Value
    $privateStorageTableDnsZoneResourceId  = $result.Outputs.privateStorageTableDnsZoneResourceId.Value
}
elseif($vnetFuncSubnetResourceId -eq "" -or $vnetPrivateEndpointSubnetResourceId -eq "" -or $privateStorageBlobDnsZoneResourceId -eq "" -or $privateStorageQueueDnsZoneResourceId -eq "" -or $privateStorageTableDnsZoneResourceId -eq "") {
    throw "If networkingrg is not specified, then all networking resource id parameters must be specified"
}
else {
    Write-Host -ForegroundColor Green "Using existing networking resources"
}

# sla solution deployment




