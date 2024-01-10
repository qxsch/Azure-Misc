param(
    [Parameter(Mandatory=$true)]
    [string] $slareportingrg,


    [string] $workspaceName = "",
    [ValidateRange(30, 730)]
    [int]    $workspaceSlaTableRetentionINDays = 30,
    [string] $dataCollectionRuleName = "",
    [string] $dataCollectionEndpointName = "",
    [string] $functionAppName = "",
    [string] $storageAccountName = "",
    [string] $hostingPlanName = "",
    [string] $hostingPlanSku = "Premium0V3",
    [string] $hostingPlanSkuCode = "P0V3",
    [int]    $hostingPlanWorkerCount =  1,
    [bool]   $hostingPlanZoneRedundant = $false,
    [ValidateSet("full", "full-without-role-assignment", "just-log-pipeline")]
    [string] $deplyomentFeatures = "full",
    $functionIngressRestrictions = $null,
    
    # either the networkingrg parametermust be specified (in case the networking resources must be deployed) you can also optionally specify the following parameters
    [string]$networkingrg = "",
    [string]$vnetName = "",
    [string]$functionSubnetNam = "",
    [string]$privateEndpointSubnetName = "",
    [string]$vnetAddressPrefix = "",
    [string]$functionSubnetAddressPrefix = "",
    [string]$privateEndpointSubnetAddressPrefix = "",
    # or all of the following parameters must be specified (in case the networking resources already exist and networkingrg parameter is not specified)
    [string]$vnetFuncSubnetResourceId = "",
    [string]$vnetPrivateEndpointSubnetResourceId = "",
    [string]$privateStorageBlobDnsZoneResourceId = "",
    [string]$privateStorageQueueDnsZoneResourceId = "",
    [string]$privateStorageTableDnsZoneResourceId = ""
)

if($deplyomentFeatures -eq "just-log-pipeline") {
    throw "Please use the non-private deployment templates (template.json and parameters.json)"
}


# optional baseline networking resources deployment
if( $networkingrg -ne "" ) {
    if($vnetFuncSubnetResourceId -ne "" -or $vnetPrivateEndpointSubnetResourceId -ne "" -or $privateStorageBlobDnsZoneResourceId -ne "" -or $privateStorageQueueDnsZoneResourceId -ne "" -or $privateStorageTableDnsZoneResourceId -ne "") {
        throw "If -networkingrg is being used, then all networking resource id parameters must be empty (do not use -vnetFuncSubnetResourceId, -vnetPrivateEndpointSubnetResourceId, -privateStorageBlobDnsZoneResourceId, -privateStorageQueueDnsZoneResourceId, -privateStorageTableDnsZoneResourceId)"
    }

    Write-Host -ForegroundColor Green "Deploying networking resources to $networkingrg"
    # setting paramaters (optional)
    $params = @{}
    if($vnetName -ne "") { $params["vnetName"] = $vnetName }
    if($functionSubnetName -ne "") { $params["functionSubnetName"] = $functionSubnetName }
    if($privateEndpointSubnetName -ne "") { $params["privateEndpointSubnetName"] = $privateEndpointSubnetName }
    if($vnetAddressPrefix -ne "") { $params["vnetAddressPrefix"] = $vnetAddressPrefix }
    if($functionSubnetAddressPrefix -ne "") { $params["functionSubnetAddressPrefix"] = $functionSubnetAddressPrefix }
    if($privateEndpointSubnetAddressPrefix -ne "") { $params["privateEndpointSubnetAddressPrefix"] = $privateEndpointSubnetAddressPrefix }
    # deploying
    $result = New-AzResourceGroupDeployment -ResourceGroupName $networkingrg -TemplateFile .\tmpls\private\privatenetworking-template.json @params
    # $result.Outputs.vnetResourceId.Value
    $vnetFuncSubnetResourceId              = $result.Outputs.vnetFuncSubnetResourceId.Value
    $vnetPrivateEndpointSubnetResourceId   = $result.Outputs.vnetPrivateEndpointSubnetResourceId.Value
    $privateStorageBlobDnsZoneResourceId   = $result.Outputs.privateStorageBlobDnsZoneResourceId.Value
    $privateStorageQueueDnsZoneResourceId  = $result.Outputs.privateStorageQueueDnsZoneResourceId.Value
    $privateStorageTableDnsZoneResourceId  = $result.Outputs.privateStorageTableDnsZoneResourceId.Value

    Write-Host -ForegroundColor Green "Output:"
    foreach($o in $result.Outputs.GetEnumerator()) {
        Write-Host -ForegroundColor Green ("{0,20}  =  {1}" -f @($o.Key, $o.Value.Value))
    }

    Write-Host "Tip: You can skip networking deployment in the futre (please remove -networkingrg parameter and add the following ones instead):   -vnetFuncSubnetResourceId `"$vnetFuncSubnetResourceId`" -vnetPrivateEndpointSubnetResourceId `"$vnetPrivateEndpointSubnetResourceId`" -privateStorageBlobDnsZoneResourceId `"$privateStorageBlobDnsZoneResourceId`" -privateStorageQueueDnsZoneResourceId `"$privateStorageQueueDnsZoneResourceId`" -privateStorageTableDnsZoneResourceId `"$privateStorageTableDnsZoneResourceId`""
}
elseif($vnetFuncSubnetResourceId -eq "" -or $vnetPrivateEndpointSubnetResourceId -eq "" -or $privateStorageBlobDnsZoneResourceId -eq "" -or $privateStorageQueueDnsZoneResourceId -eq "" -or $privateStorageTableDnsZoneResourceId -eq "") {
    throw "If -networkingrg is not used, then all networking resource id parameters must be specified (use -vnetFuncSubnetResourceId, -vnetPrivateEndpointSubnetResourceId, -privateStorageBlobDnsZoneResourceId, -privateStorageQueueDnsZoneResourceId, -privateStorageTableDnsZoneResourceId)"
}
else {
    Write-Host -ForegroundColor Green "Using existing networking resources"
}


# sla solution deployment
Write-Host -ForegroundColor Green "Deploying sla reporting resources to $slareportingrg"

# setting paramaters (optional)
$params = @{}
$params["workspaceSlaTableRetentionINDays"] = $workspaceSlaTableRetentionINDays
$params["hostingPlanSku"] = $hostingPlanSku
$params["hostingPlanSkuCode"] = $hostingPlanSkuCode
$params["hostingPlanWorkerCount"] = $hostingPlanWorkerCount
$params["hostingPlanZoneRedundant"] = $hostingPlanZoneRedundant
$params["vnetFuncSubnetResourceId"] = $vnetFuncSubnetResourceId
$params["vnetPrivateEndpointSubnetResourceId"] = $vnetPrivateEndpointSubnetResourceId
$params["privateStorageBlobDnsZoneResourceId"] = $privateStorageBlobDnsZoneResourceId
$params["privateStorageQueueDnsZoneResourceId"] = $privateStorageQueueDnsZoneResourceId
$params["privateStorageTableDnsZoneResourceId"] = $privateStorageTableDnsZoneResourceId
$params["deplyomentFeatures"] = $deplyomentFeatures
if($workspaceName -ne "") { $params["workspaceName"] = $workspaceName }
if($dataCollectionRuleName -ne "") { $params["dataCollectionRuleName"] = $dataCollectionRuleName }
if($dataCollectionEndpointName -ne "") { $params["dataCollectionEndpointName"] = $dataCollectionEndpointName }
if($storageAccountName -ne "") { $params["storageAccountName"] = $storageAccountName }
if($hostingPlanName -ne "") { $params["hostingPlanName"] = $hostingPlanName }
if($functionAppName -ne "") { $params["functionAppName"] = $functionAppName }
if($null -ne $functionIngressRestrictions) { $params["functionIngressRestrictions"] = $functionIngressRestrictions }
# deploying
$result = New-AzResourceGroupDeployment -ResourceGroupName $slareportingrg -TemplateFile .\tmpls\private\slareporting-template.json @params
# output
Write-Host -ForegroundColor Green "Output:"
foreach($o in $result.Outputs.GetEnumerator()) {
    Write-Host -ForegroundColor Green ("{0,20}  =  {1}" -f @($o.Key, $o.Value.Value))
}

