param(
    [Parameter(Mandatory=$true)]
    [string]$DceURI,
    [Parameter(Mandatory=$true)]
    [string]$DcrImmutableId

)


# yes batch submit is supported, but this uses more demo time and people can see it working
# (data will not be directly visible within log analytics due to delay in ingestion and processing)


$data = [PSCustomObject]@{
    "DCR" = [PSCustomObject]@{
        "Table"          = "sla_data_CL"
        "DceURI"         = $DceURI
        "DcrImmutableId" = $DcrImmutableId
        "Token"          = (Get-AzAccessToken -ResourceUrl "https://monitor.azure.com/")
    }
}

for($i = 0; $i -lt 25; $i++) {
    Write-Host ( "Submitting storage SLA failure metric " + ($i + 1))
    # Sending the data to Log Analytics via the DCR!
    $jsonBody = (@(
        @{
                                 
            "SubscriptionId" =   "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
            "ResourceId" =       "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/test/providers/Microsoft.Storage/storageAccounts/testaccount"
            "ResourceType" =     "Storage Account"
            "UptimePercentage" = ([float]0.0)
        }
    ) | ConvertTo-Json -AsArray)
    $headers = @{"Authorization" = ("Bearer $token" + $data.DCR.Token.Token ); "Content-Type" = "application/json" }
    $uri = ( $data.DCR.DceURI + "/dataCollectionRules/" + $data.DCR.DcrImmutableId + "/streams/Custom-" + $data.DCR.Table + "?api-version=2021-11-01-preview" )
    try {
        Invoke-RestMethod -Uri $uri -Method "Post" -Body $jsonBody -Headers $headers | Out-Null
    }
    catch {
        Write-Error  ( "Failed to send storage SLA failure metric")
    }

}
