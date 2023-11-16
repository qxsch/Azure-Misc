param($Context)

# $Context.Input    could be holding the subscription id (and then use it for Search-AzGraph -SubscriptionId )

Import-Module Az.ResourceGraph -ErrorAction Stop

function GetTokenExpiryInMinutes {
    param(
        [Parameter(Mandatory, Position=0)]
        $Token
    )

    if($Token.ExpiresOn) {
        return (($Token.ExpiresOn.UtcDateTime) - (Get-Date -AsUTC)).TotalMinutes
    }
    else {
        return 0
    }
}


$BatchSize = 950

$Query = "resources 
| where ['tags'].slareporting != 'disabled'
| where ( 
    ( ['type'] == 'microsoft.storage/storageaccounts' and properties.provisioningState =~ 'succeeded' ) or 
    ( ['type'] == 'microsoft.web/sites' and ['kind'] !contains 'function' and ['kind'] !contains 'workflow' and properties.state in~ ('running') ) or 
    ( ['type'] == 'microsoft.sql/servers/databases' and sku.name !~ 'system' and kind !contains('system') and properties.status =~'online' )
)"



$baseData = [PSCustomObject]@{
    "DCR" = [PSCustomObject]@{
        "Table"          = "sla_data_CL"
        "DceURI"         = $env:DceURI
        "DcrImmutableId" = $env:DcrImmutableId
        "Token"          = (Get-AzAccessToken -ResourceUrl "https://monitor.azure.com/")
    }
    "Tokens" = [PSCustomObject]@{
        "StorageAccount" = (Get-AzAccessToken -ResourceUrl "https://storage.azure.com/")
        "SQLDatabase" = (Get-AzAccessToken -ResourceUrl "https://database.windows.net/")
    }
}

$graphResult = $null
while($true) {
    if($graphResult.SkipToken) {
        $graphResult = Search-AzGraph -Query $Query -First $BatchSize -SkipToken $graphResult.SkipToken
    }
    else {
        $graphResult = Search-AzGraph -Query $Query -First $BatchSize
    }

    # regenerating keys?
    if((GetTokenExpiryInMinutes -Token $baseData.DCR.Token) -lt 25) {
        $baseData.DCR.Token = (Get-AzAccessToken -ResourceUrl "https://monitor.azure.com/")
    }
    if((GetTokenExpiryInMinutes -Token $baseData.Tokens.StorageAccount) -lt 25) {
        $baseData.Tokens.StorageAccount = (Get-AzAccessToken -ResourceUrl "https://storage.azure.com/")
    }
    if((GetTokenExpiryInMinutes -Token $baseData.Tokens.SQLDatabase) -lt 25) {
        $baseData.Tokens.SQLDatabase = (Get-AzAccessToken -ResourceUrl "https://database.windows.net/")
    }
    

    # processing result batch
    $ParallelTasks = @()
    foreach($r in $graphResult.data) {
        if($r.type -eq "microsoft.storage/storageaccounts") {
            $ParallelTasks += (Invoke-DurableActivity -FunctionName 'AzStorageAccountActivity' -Input (([PSCustomObject]@{
                "DCR" = $baseData.DCR
                "SubscriptionId" = $r.subscriptionId
                "ResourceId" = $r.id
                "ResourceType" = "Storage Account"
                "PrimaryEndpoints" = $r.properties.primaryEndpoints
                "AccessToken" = $baseData.Tokens.StorageAccount.Token
            }) | ConvertTo-Json -Depth 10 -Compress) -NoWait)
        }
        elseif($r.type -eq "microsoft.web/sites") {
            $k = ([string]$r.kind).ToLower()
            if($k.Contains("function")) { # function app
            }
            elseif($k.Contains("workflow")) { # logic app
            }
            elseif($k.Contains("app")) { # web app
                $ParallelTasks += (Invoke-DurableActivity -FunctionName 'AzWebCallActivity' -Input (([PSCustomObject]@{
                    "DCR" = $baseData.DCR
                    "SubscriptionId" = $r.subscriptionId
                    "ResourceId" = $r.id
                    "ResourceType" = "Web App"
                    "Url" = $r.properties.hostNames[0]
                }) | ConvertTo-Json -Depth 10 -Compress) -NoWait)
            }
        }
        elseif($r.type -eq "microsoft.sql/servers/databases") {
            $ParallelTasks += (Invoke-DurableActivity -FunctionName 'AzSqlDbActivity' -Input (([PSCustomObject]@{
                "DCR" = $baseData.DCR
                "SubscriptionId" = $r.subscriptionId
                "ResourceId" = $r.id
                "ResourceType" = "SQL Database"
                "ServerName"   = ( (($r.id -split '/')[8]) + ".database.windows.net" )
                "DatabaseName" = $r.name
                "AccessToken" = $baseData.Tokens.SQLDatabase.Token
            }) | ConvertTo-Json -Depth 10 -Compress) -NoWait)
        }
    }
    # consume activity results
    if($ParallelTasks.Count -gt 0) {
        Wait-ActivityFunction -Task $ParallelTasks | Out-Null
    }
    

    if ($graphResult.data.Count -lt $BatchSize) {
        break;
    }
}


"Done"

