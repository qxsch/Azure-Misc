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
    $functionIngressRestrictions = $null
)

# sla solution deployment
Write-Host -ForegroundColor Green "Deploying sla reporting resources to $slareportingrg"

# setting paramaters (optional)
$params = @{}
$params["workspaceSlaTableRetentionINDays"] = $workspaceSlaTableRetentionINDays
$params["hostingPlanSku"] = $hostingPlanSku
$params["hostingPlanSkuCode"] = $hostingPlanSkuCode
$params["hostingPlanWorkerCount"] = $hostingPlanWorkerCount
$params["hostingPlanZoneRedundant"] = $hostingPlanZoneRedundant
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

