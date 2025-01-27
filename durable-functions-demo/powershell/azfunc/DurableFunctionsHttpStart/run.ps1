using namespace System.Net

param($Request, $TriggerMetadata)

$name = "" + $Request.Query.name

$InstanceId = Start-DurableOrchestration -FunctionName "DurableFunctionsOrchestrator" -Input $name
Write-Host "Started orchestration with ID = '$InstanceId' and passed '$name' as input"

$Response = New-DurableOrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId
Push-OutputBinding -Name Response -Value $Response
