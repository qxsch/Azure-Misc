param($activitiyJson)

if($activitiyJson.DCR) {
    $data = $activitiyJson
}
else {
    $data = ( $activitiyJson | ConvertFrom-Json -Depth 10)
}

<#
$data = [PSCustomObject]@{
    "DCR" = [PSCustomObject]@{
        "Table"          = ""
        "DceURI"         = ""
        "DcrImmutableId" = ""
        "Token" = [PSCustomObject]@{
            "Type" = ""
            "Token" =  ""
            "ExpiresOn" = [DateTimeOffset]""
            ...
        }
       
    "SubscriptionId" = ""
    "ResourceId" = ""
    "ResourceType" = ""
    "Url" = ""
}
#>

$failedTries = 0
while($failedTries -lt 4) {
    try {
        $result = Invoke-WebRequest -Uri ( $data.Url )
        if($result.StatusCode -lt 500 ) {
            break
        }
    }
    catch { }
    $failedTries++
    Start-Sleep -Seconds 0.1
}

# Sending the data to Log Analytics via the DCR!
$jsonBody = (@(
    @{
        "SubscriptionId" =   ([string]$data.SubscriptionId)
        "ResourceId" =       ([string]$data.ResourceId)
        "ResourceType" =     ([string]$data.ResourceType)
        "UptimePercentage" = ([float](1 -  $failedTries / 4))
    }
) | ConvertTo-Json -AsArray)
$headers = @{"Authorization" = ("Bearer $token" + $data.DCR.Token.Token ); "Content-Type" = "application/json" }
$uri = ( $data.DCR.DceURI + "/dataCollectionRules/" + $data.DCR.DcrImmutableId + "/streams/Custom-" + $data.DCR.Table + "?api-version=2021-11-01-preview" )
try {
    Invoke-RestMethod -Uri $uri -Method "Post" -Body $jsonBody -Headers $headers | Out-Null
}
catch {
    Write-Error  ( "Failed to send SLA metric for Resource Id " + ([string]$data.ResourceId) )
}

