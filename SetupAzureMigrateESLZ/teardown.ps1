# ----- BEGIN OF CONFIGURATION -----
$subscriptionid      = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
$resourcegroup       = 'RGNAMEHERE'
# ----- END OF CONFIGURATION -----


# select subscription
Select-AzSubscription -SubscriptionId $subscriptionid -Scope Process | Out-Null

# delete resource group
Remove-AzResourceGroup -Name $resourcegroup -Force
