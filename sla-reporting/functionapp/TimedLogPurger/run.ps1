# Input bindings are passed in via param block.
param($Timer, $starter)

# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}


# purge instance history older than 14 days
$uri = (
    $starter["baseUrl"] + 
    '/instances?' + $starter["requiredQueryStringParameters"] +
    '&taskHub=' + [System.Web.HttpUtility]::UrlEncode($env:WEBSITE_SITE_NAME) +
    '&createdTimeFrom=' + [System.Web.HttpUtility]::UrlEncode((Get-Date (Get-Date).AddYears(-300) -Format "yyyy-MM-dd")) +
    '&createdTimeTo=' + [System.Web.HttpUtility]::UrlEncode((Get-Date (Get-Date).AddDays(-14) -Format "yyyy-MM-dd"))
)

try {
    $result = Invoke-WebRequest -Method Delete -Uri $uri
    Write-Host ( "Deleted " + ([int]($result.Content | ConvertFrom-Json -Depth 10).instancesDeleted)  + " instances")
}
catch {
    if($_.Exception.Response -and $_.Exception.Response.StatusCode -and $_.Exception.Response.StatusCode -eq 404) {
        Write-Host "Nothing to delete"
    }
    else {
        Write-Host ( "Failed with " + $_.Exception.Message )
    }
}