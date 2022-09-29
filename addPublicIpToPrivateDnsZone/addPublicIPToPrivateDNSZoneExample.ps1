$zoneSubscription  = 'NETWORK ZONE'
$zoneResourceGroup = 'dnszones'

$dnsFqdn = 'mypostgres.postgres.database.azure.com'


$dnsZone = (($dnsFqdn -split '\.')[1..10] -join '.')
$dnsName = ($dnsFqdn -split '\.')[0]

#Select-AzSubscription $zoneSubscription

$zone = Get-AzPrivateDnsZone -ResourceGroupName $zoneResourceGroup -Name "privatelink.$dnsZone"

$record = ($zone | Get-AzPrivateDnsRecordSet -RecordType A -Name $dnsName -ErrorAction Ignore)


if($null -eq $record) {
    $addrs = @()
    $ipAddrs = @()
    foreach($a in [System.Net.Dns]::GetHostAddresses($dnsFqdn)) {
        if($a.IPAddressToString -like '*.*.*.*') {
            $ipAddrs += New-AzPrivateDnsRecordConfig -IPv4Address $a.IPAddressToString
            $addrs += $a.IPAddressToString
        }
    }
    Write-Host ("Creating the record for $dnsName (" + ( $addrs -join ', ') + ") in private zone $dnsZone")
    $zone | New-AzPrivateDnsRecordSet -RecordType A -Name $dnsName -TTL 3600 -PrivateDnsRecords $ipAddrs
}
else {
    Write-Host ("The record for $dnsName (" + ( $record.Records.IPv4Address -join ', ' ) + ") already exists in private zone $dnsZone")
}