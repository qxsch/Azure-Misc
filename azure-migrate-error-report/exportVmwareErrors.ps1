<#
.SYNOPSIS
    This script retrieves information about machines in a specified VMware site within an Azure resource group and exports error details to CSV files.

.DESCRIPTION
    The script performs the following tasks:
    - Retrieves machine information from the specified VMware site within an Azure resource group.
    - Checks for discovery errors and categorizes them by operating system type.
    - Exports detailed error information to a CSV file under $errorsCsvPath.
    - Groups errors by operating system type and exports the grouped data to another CSV file under $groupedErrorsCsvPath.

.PARAMETER resourceGroupName
    The name of the Azure resource group containing the VMware site.

.PARAMETER siteName
    The name of the VMware site.

.PARAMETER subscriptionId
    The Azure subscription ID. If not provided, the script will use the subscription ID from the current Azure context.

.PARAMETER responseJsonPath
    The file path template for saving the JSON response from the Azure REST API. Default is "response.{0}.json".

.PARAMETER errorsCsvPath
    The file path for exporting detailed error information to a CSV file. Default is "errors.csv".

.PARAMETER groupedErrorsCsvPath
    The file path for exporting grouped error information to a CSV file. Default is "groupedErrors.csv".

.EXAMPLE
    .\Get-MachineErrors.ps1 -resourceGroupName "MyResourceGroup" -siteName "MyVMwareSite"

.NOTES
    - Requires the Az module.
    - The script will iterate through multiple pages of results if necessary, up to a maximum of 10,000 iterations.
#>
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$resourceGroupName = "",
    [Parameter(Mandatory=$true, Position=1)]
    [string]$siteName = "",

    [string]$subscriptionId = "",

    [string]$responseJsonPath = "response.{0}.json",
    [string]$errorsCsvPath = "errors.csv",
    [string]$groupedErrorsCsvPath = "groupedErrors.csv"
)

if($subscriptionId -eq "") {
    $subscriptionId = (Get-AzContext).Subscription.Id
}

$errorsByOsType = @{}     
$csvContent = @()

# Get the information about the machines in the project
# GET https://management.azure.com/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.OffAzure/VMwareSites/{siteName}/machines?api-version=2020-01-01
$iteration = 0
$response = (Invoke-AzRestMethod `
                -SubscriptionId $subscriptionId `
                -ResourceGroupName $resourceGroupName `
                -ResourceProviderName "Microsoft.OffAzure" `
                -ResourceType "VMwareSites" `
                -Name "$siteName/machines" `
                -ApiVersion '2020-01-01' `
                -Method GET).Content | ConvertFrom-Json -Depth 100
# saving the response to a file
if($responseJsonPath -ne "") {
    $response.value | ConvertTo-Json -Depth 100 | Out-File -FilePath ($responseJsonPath -f $iteration)
}


while($null -ne $response -and $response.value -and $response.value.Length -gt 0 -and $iteration -lt 10000) {
    Write-Host "Iteration: $iteration"
    $iteration++
    # Check for discovery errors
    foreach ($machine in $response.value) {
        if ($machine.properties.errors) {
            if($machine.properties.hostName -eq "") {
                Write-Host -ForegroundColor Yellow "empty hostName for machine $($machine.name) (DC-Scope: $($machine.properties.dataCenterScope)) - skipping..."
                continue
            }
            $errorIds = @()
            foreach ($e in $machine.properties.errors) {
                if(-not $errorsByOsType.ContainsKey($machine.properties.operatingSystemDetails.osType)) {
                    $errorsByOsType[$machine.properties.operatingSystemDetails.osType] = @{}
                }
                if($errorsByOsType[$machine.properties.operatingSystemDetails.osType].ContainsKey($e.id)) {
                    $errorsByOsType[$machine.properties.operatingSystemDetails.osType][$e.id]++
                }
                else {
                    $errorsByOsType[$machine.properties.operatingSystemDetails.osType][$e.id] = 1
                }
                if($errorIds -notcontains $e.id) {
                    $errorIds += $e.id
                    $csvContent += [PSCustomObject]@{
                        ObjectName             = $machine.name
                        DCSCope                = $machine.properties.dataCenterScope
                        Hostname               = $machine.properties.hostName
                        OsType                 = $machine.properties.operatingSystemDetails.osType
                        ErrorId                = $e.id
                        ErrorCode              = $e.code
                        ErrorMessage           = $e.message
                        ErrorSeverity          = $e.severity
                        ErrorSummaryMessage    = $e.summaryMessage
                        ErrorPossibleCauses    = $e.possibleCauses
                        ErrorRecommendedAction = $e.recommendedAction
                    }
                }
            }
        }
    }
    # no next page, break the loop
    if($null -eq $response.nextLink -or $response.nextLink -eq "") {
        break
    }
    # get the next page of the response
    $response = (Invoke-AzRestMethod -Method GET -Uri $response.nextLink).Content | ConvertFrom-Json -Depth 100
    # saving the response to a file
    if($responseJsonPath -ne "") {
        $response.value | ConvertTo-Json -Depth 100 | Out-File -FilePath ($responseJsonPath -f $iteration)
    }
}


# Export the PowerShell object to a CSV file
$csvContent | Export-Csv -Path $errorsCsvPath -NoTypeInformation


$groupedErrors = @()
foreach ($osType in $errorsByOsType.Keys) {
    foreach ($errorId in $errorsByOsType[$osType].Keys) {
        $groupedErrors += [PSCustomObject]@{
            OsType = $osType
            ErrorId = $errorId
            Count = $errorsByOsType[$osType][$errorId]
        }
    }
}
# Export the PowerShell object to a CSV file
$groupedErrors | Export-Csv -Path $groupedErrorsCsvPath -NoTypeInformation
