# ----- BEGIN OF CONFIGURATION -----
$subscriptionid      = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
$resourcegroup       = 'RGNAMEHERE'
$migrateprojectname  = 'PROJECTNAMEHERE'
$location            = 'westus2'

$privatednszoneresourceid  = '/subscriptions/zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz/resourceGroups/RGNAMEHERE/providers/Microsoft.Network/privateDnsZones/privatelink.prod.migration.windowsazure.com'
$subnetresourceid          = '/subscriptions/yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy/resourceGroups/RGNAMEHERE/providers/Microsoft.Network/virtualNetworks/VNETNAMEHERE/subnets/SUBNETNAMEHERE'
# ----- END OF CONFIGURATION -----

# select subscription
Select-AzSubscription -SubscriptionId $subscriptionid -Scope Process | Out-Null

# get subnet location
$subnetlocation = (Get-AzResource -ResourceId ((( $subnetresourceid -split '/' ) | Select-Object -First 9) -join '/') -ErrorAction Stop).Location

# create private az migrate
$result = New-AzResourceGroupDeployment -ResourceGroupName $resourcegroup -TemplateFile .\001_azMigrateTemplate.json `
    -migrateProjectName $migrateprojectname `
    -location $location `
    -subnetResourceId $subnetresourceid `
    -subnetLocation $subnetlocation `
    -ErrorAction Stop
# output result
$result

# get subdomain
$subdomain = [regex]::matches($result.Outputs.projecturl.Value, '^https://([^/:]+)\.privatelink\.prod\.migration\.windowsazure\.com').groups[1].Value
# get private ip
$privateip = (Get-AzNetworkInterface -ResourceGroupName $resourcegroup | Where-Object { $_.Name.StartsWith($migrateprojectname + 'pe.') } | Select-Object -First 1).IpConfigurations.PrivateIpAddress
# output subdomain and private ip
Write-Host "Subdomain : $subdomain"
Write-Host "Private IP: $privateip"

# create private dns record
New-AzPrivateDnsRecordSet -ParentResourceId $privatednszoneresourceid `
    -Name $subdomain `
    -RecordType A `
    -Ttl 3600 `
    -PrivateDnsRecords (New-AzPrivateDnsRecordConfig -IPv4Address $privateip)


# 10.172.157.101
# https://b72766a2-64d5-4d8e-b5c8-c272b00fb28a-isv.cus.hub.privatelink.prod.migration.windowsazure.com/resources/b72766a2-64d5-4d8e-b5c8-c272b00fb28a

