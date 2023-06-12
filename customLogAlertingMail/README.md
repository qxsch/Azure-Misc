# Custom Log Alerting Mail

*Goal:* Generate an alert mail, that contains the log analytics query result within the mail body.

## Setup

1. Create an app registration in Azure AD with the following permissions:
    - Application Insights: `Data.Read` 
    - Azure Log Analytics: `Data.Read`

   For more information Read here: https://learn.microsoft.com/en-us/azure/azure-monitor/app/app-insights-azure-ad-api

1. Give the app registration ``Reader`` role to application insights and log anayltics workspaces (where it should read data from)

1. Create a resource group

1. Set the correct values within the ``logicapp-params.json`` file

1. Deploy the logic app (key vault & action group) into the resource group: ``New-AzResourceGroupDeployment -ResourceGroupName <resource group name> -TemplateFile .\logicapp-template.json -TemplateParameterFile .\logicapp-params.json``

1. Add the secret and client id of the app registration to the key vault

1. Give the logic app ``Key Vault Secrets User` role to the keyvault

1. Authorize the logic app office365 API connection. (This is required to send the mail and you find the "Authorize" button within the "Edit API Connection" blade of the service connection called "office365")

1. Create a log analytics alert rule and set the newly created action group

