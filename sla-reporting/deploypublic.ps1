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

if($null -eq $functionIngressRestrictions) {
    Write-Host -ForegroundColor Yellow "Using default function ingress restrictions (allow all)"
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
# setting function app name
if($functionAppName -eq "") {
    $functionAppName = $result.Outputs.functionAppName.Value
}


if(Test-Path .\functionapp.zip -PathType Leaf) {
    Write-Host "Removing old functionapp.zip"
    Remove-Item .\functionapp.zip -Force | Out-Null
}
Write-Host "Creating functionapp.zip"
Compress-Archive -Path .\functionapp\* -DestinationPath .\functionapp.zip -Force

# checking settings
$settings = Get-AzFunctionAppSetting -ResourceGroupName $slareportingrg -Name $functionAppName 
if($settings.SCM_DO_BUILD_DURING_DEPLOYMENT -and $settings.SCM_DO_BUILD_DURING_DEPLOYMENT -ne "false") {
    Write-Host "Disabling build during deployment"
    Update-AzFunctionAppSetting -ResourceGroupName $slareportingrg -Name $functionAppName -AppSetting @{"SCM_DO_BUILD_DURING_DEPLOYMENT" = "false"} | Out-Null
}
Write-Host "Publishing function app"
Publish-AzWebApp -ResourceGroupName $slareportingrg -Name $functionAppName -ArchivePath .\functionapp.zip -Force | Out-Null
