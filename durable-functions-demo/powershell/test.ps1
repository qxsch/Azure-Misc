param(
    [string] $resourceGroupName = "durablefunc",
    [string]$functionName = ''
)


if($functionName.Trim() -eq '') {
    $fa = Get-AzFunctionApp -ResourceGroupName $resourceGroupName
    if($fa.Count -eq 0) {
        throw "No function apps found in resource group $resourceGroupName"
    }
    elseif($fa.Count -gt 1) {
        Write-Host -ForegroundColor Yellow "Multiple function apps found in resource group $resourceGroupName. Using the first one. To specify a function app, use the -functionName parameter."
        $fa = $fa[0]
    }
}
else {
    $fa = Get-AzFunctionApp -ResourceGroupName $resourceGroupName -Name $functionName
    if(-not $fa) {
        throw "Function app $functionName not found in resource group $resourceGroupName"
    }
}

if($fa.Status -ne 'Running') {
    throw "Function app $($fa.Name) is not running. Current status: $($fa.Status)"
}

Write-Host ("Domain name: {0}" -f $fa.DefaultHostName)


Write-Host "Creating a durable function instance"
$durableInstance = Invoke-RestMethod "https://$($fa.DefaultHostName)/api/httpdurable?name=World"

$durableInstance

$checkResult = $true
while($checkResult) {
    Write-Host "Polling status of the durable function instance $($durableInstance.id)"
    $result = Invoke-RestMethod $durableInstance.statusQueryGetUri
    $checkResult = $result.runtimeStatus -eq 'Running'
    Write-Host "   Current status: $($result.runtimeStatus)      Custom Status: $($result.customStatus)"
    Start-Sleep -Seconds 2
}


Write-Host "Durable function instance completed"
$result

Write-Host "Output:"
$result.output
