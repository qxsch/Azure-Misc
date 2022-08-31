$t = Get-AzAccessToken

Select-AzSubscription "Playground"


# $en = Get-AzEventHubNamespace -ResourceGroupName mgmtaudit -Name mwmgmtaudit
# $eh = Get-AzEventHub -ResourceGroupName mgmtaudit -Namespace mwmgmtaudit -Name mgmtaudit
# $ehr = Get-AzEventHubAuthorizationRule -ResourceGroupName mgmtaudit -Namespace mwmgmtaudit -EventHubName mgmtaudit -Name mysender

$enr = Invoke-RestMethod -Method Get -Headers @{"Authorization" = ( $t.Type + " " + $t.Token )} -Uri ("https://management.azure.com/subscriptions/" + [System.Web.HttpUtility]::UrlEncode((Get-AzContext).Subscription.Id) + "/resourceGroups/" + [System.Web.HttpUtility]::UrlEncode("mgmtaudit") + "/providers/Microsoft.EventHub/namespaces/" + [System.Web.HttpUtility]::UrlEncode("mwmgmtaudit") + "/authorizationRules/" + [System.Web.HttpUtility]::UrlEncode("RootManageSharedAccessKey") + "?api-version=2021-06-01-preview")


$b = @{
    "properties" = @{
      "storageAccountId" = $null
      "workspaceId" = $null
      "eventHubAuthorizationRuleId" = $enr.id
      "eventHubName" = "mgmtaudit"
      "logs" = @(
        @{
          "category" = "Administrative"
          "enabled" = $true
        }
        <#
        @{
          "category" = "Policy"
          "enabled" = $true
        }
        #>
      )
    }
  }

Write-Host ($b | ConvertTo-Json -Depth 10)

# create assignment - https://docs.microsoft.com/en-us/rest/api/monitor/management-group-diagnostic-settings/create-or-update?tabs=HTTP
Invoke-RestMethod -Method Put -Headers @{"Authorization" = ( $t.Type + " " + $t.Token ) ; "Content-Type" = "application/json" } -Body ($b | ConvertTo-Json -Depth 10) -Uri "https://management.azure.com/providers/microsoft.management/managementGroups/auditmgmt/providers/microsoft.insights/diagnosticSettings/setting1?api-version=2020-01-01-preview"


# test settings - https://docs.microsoft.com/en-us/rest/api/monitor/management-group-diagnostic-settings/list?tabs=HTTP
(Invoke-RestMethod -Method Get -Headers @{"Authorization" = ( $t.Type + " " + $t.Token )} -Uri "https://management.azure.com/providers/microsoft.management/managementGroups/auditmgmt/providers/microsoft.insights/diagnosticSettings?api-version=2020-01-01-preview").value
