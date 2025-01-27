using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)


# Interact with query parameters or the body of the request.
$name = $Request.Query.Name


function hello {
    param($name)
    Start-Sleep -Seconds 6
    Write-Host "Name: $name"

    "Hello $name!"
}


$output = @()

$output += hello -name $name

$output += hello -name 'Tokyo'

$output += hello -name 'Seattle'

$output += hello -name 'London'





# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $output
})
