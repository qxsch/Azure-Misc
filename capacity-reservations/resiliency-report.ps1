<#
.SYNOPSIS
    Generates an Excel resiliency report covering VM disaster-recovery status and capacity-reservation utilisation.

.DESCRIPTION
    Uses Azure Resource Graph to collect:
      - All VMs and their power state, size, location, zones, and capacity-reservation group association.
      - Azure Site Recovery replication status to flag VMs without DR.
      - Capacity Reservation Groups (including shared / cross-subscription CRGs) and their member reservations.
      - Reservation utilisation analysis (provisioned vs consumed cores).
      - Logical-to-physical availability zone mappings per subscription.
      - Capacity reservation recommendations: what is needed vs what is provisioned,
        broken down by SKU, region, and physical availability zone.

    Outputs an Excel workbook with the following sheets:
      1) SubscriptionSummary        – per-subscription VM count, DR-protected count, capacity-reservation counts.
      2) VMs                        – every VM with DR flag, associated CRG, power state, physical zone, etc.
      3) CapacityReservations       – every CRG / CR with SKU, provisioned capacity, consumed VMs, zones, sharing info.
      4) DRGaps                     – VMs that do NOT have Site Recovery replication configured.
      5) ZoneMappings               – logical-to-physical zone mappings per subscription and region.
      6) CapacityRecommendations    – per SKU / region / physical zone: VM demand vs reserved capacity with gap analysis.

.PARAMETER ExcelFile
    Path to the output Excel file. Defaults to resiliency-report.xlsx in the current directory.

.PARAMETER ManagementGroup
    Name or ID of a management group. All child subscriptions are included.

.PARAMETER Subscriptions
    One or more subscriptions. Accepts subscription objects (Get-AzSubscription output),
    subscription GUIDs, or subscription display names. Supports pipeline input.

.PARAMETER SharedCapacitySubscriptionId
    Optional. The subscription ID that owns the shared Capacity Reservation Groups.
    When provided, CRGs are queried directly from this subscription and zone mappings
    for capacity reservations use this subscription's logical-to-physical mapping.

.PARAMETER IncludeSharedCapacityReservations
    When set, the report also discovers Capacity Reservation Groups shared TO the target
    subscriptions from other subscriptions (cross-subscription sharing).

.PARAMETER Verbose
    Standard PowerShell verbose output for progress tracking.

.EXAMPLE
    .\resiliency-report.ps1 -Subscriptions "sub1","sub2","sub3" -SharedCapacitySubscriptionId "sub-that-owns-crgs"

.EXAMPLE
    Get-AzSubscription | .\resiliency-report.ps1

.EXAMPLE
    .\resiliency-report.ps1 -ManagementGroup "MyMG" -ExcelFile "C:\Reports\resiliency.xlsx"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ExcelFile = (Join-Path $PWD "resiliency-report.xlsx"),

    [Parameter()]
    [string]$ManagementGroup,

    [Parameter(ValueFromPipeline = $true)]
    [object[]]$Subscriptions,

    [Parameter()]
    [string]$SharedCapacitySubscriptionId,

    [Parameter()]
    [switch]$IncludeSharedCapacityReservations = $true
)

begin {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    #region --- Module checks ---
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        throw "Az.Accounts module is required. Install with: Install-Module Az.Accounts -Scope CurrentUser"
    }
    if (-not (Get-Module -ListAvailable -Name Az.ResourceGraph)) {
        throw "Az.ResourceGraph module is required. Install with: Install-Module Az.ResourceGraph -Scope CurrentUser"
    }
    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        throw "ImportExcel module is required. Install with: Install-Module ImportExcel -Scope CurrentUser"
    }
    Import-Module Az.Accounts -ErrorAction Stop
    Import-Module Az.ResourceGraph -ErrorAction Stop
    Import-Module ImportExcel -ErrorAction Stop
    #endregion

    # Accumulate pipeline subscriptions
    $pipelineSubscriptions = [System.Collections.Generic.List[object]]::new()
}

process {
    if ($Subscriptions) {
        foreach ($s in $Subscriptions) {
            $pipelineSubscriptions.Add($s)
        }
    }
}

end {
    #region --- Resolve subscription IDs ---
    $subscriptionIds = [System.Collections.Generic.List[string]]::new()

    if ($pipelineSubscriptions.Count -gt 0) {
        foreach ($sub in $pipelineSubscriptions) {
            if ($sub -is [Microsoft.Azure.Commands.Profile.Models.PSAzureSubscription]) {
                $subscriptionIds.Add($sub.Id)
            }
            elseif ($sub -is [string]) {
                # GUID test
                $guid = [guid]::Empty
                if ([guid]::TryParse($sub, [ref]$guid)) {
                    $subscriptionIds.Add($guid.ToString())
                }
                else {
                    # Treat as display name
                    Write-Verbose "Resolving subscription name '$sub' ..."
                    $resolved = Get-AzSubscription -SubscriptionName $sub -ErrorAction Stop
                    $subscriptionIds.Add($resolved.Id)
                }
            }
            elseif ($sub.Id) {
                # Generic object with .Id property
                $subscriptionIds.Add($sub.Id.ToString())
            }
            else {
                Write-Warning "Could not resolve subscription input: $sub"
            }
        }
    }

    if ($ManagementGroup) {
        Write-Verbose "Fetching subscriptions from management group '$ManagementGroup' ..."
        $mgQuery = "ResourceContainers | where type == 'microsoft.resources/subscriptions' | project subscriptionId"
        $mgResults = Search-AzGraph -Query $mgQuery -ManagementGroup $ManagementGroup -First 1000
        foreach ($r in $mgResults) {
            if ($subscriptionIds -notcontains $r.subscriptionId) {
                $subscriptionIds.Add($r.subscriptionId)
            }
        }
    }

    if ($subscriptionIds.Count -eq 0) {
        throw "No subscriptions specified. Use -ManagementGroup or -Subscriptions (pipeline supported: Get-AzSubscription | .\resiliency-report.ps1)."
    }

    # If SharedCapacitySubscriptionId is provided, ensure it's in the list for data collection
    if ($SharedCapacitySubscriptionId -and $subscriptionIds -notcontains $SharedCapacitySubscriptionId) {
        # We'll query CRGs from it but don't add it to the main subscription list
        # unless the user explicitly included it
        Write-Verbose "SharedCapacitySubscriptionId '$SharedCapacitySubscriptionId' will be used for CRG lookups."
    }

    Write-Host "Target subscriptions ($($subscriptionIds.Count)):" -ForegroundColor Cyan
    $subscriptionIds | ForEach-Object { Write-Host "  $_" }
    if ($SharedCapacitySubscriptionId) {
        Write-Host "Shared capacity subscription: $SharedCapacitySubscriptionId" -ForegroundColor Cyan
    }
    #endregion

    #region --- Helper: batched Resource Graph query ---
    function Invoke-ResourceGraphQuery {
        [CmdletBinding()]
        param(
            [string]$Query,
            [string[]]$SubscriptionIds,
            [int]$BatchSize = 100,
            [int]$PageSize = 1000
        )

        $allResults = [System.Collections.Generic.List[object]]::new()

        for ($i = 0; $i -lt $SubscriptionIds.Count; $i += $BatchSize) {
            $batch = $SubscriptionIds[$i..[math]::Min($i + $BatchSize - 1, $SubscriptionIds.Count - 1)]
            $skipToken = $null
            do {
                $params = @{
                    Query        = $Query
                    Subscription = $batch
                    First        = $PageSize
                }
                if ($skipToken) { $params['SkipToken'] = $skipToken }

                $result = Search-AzGraph @params
                if ($result) {
                    foreach ($row in $result) { $allResults.Add($row) }
                    $skipToken = $result.SkipToken
                }
                else { $skipToken = $null }
            } while ($skipToken)
        }

        Write-Output $allResults.ToArray()
    }
    #endregion

    #region --- Helper: get zone mappings for a subscription ---
    function Get-ZoneMappings {
        [CmdletBinding()]
        param([string]$SubscriptionId)

        $mappings = @{}
        try {
            # Switch context temporarily to the target subscription
            $response = Invoke-AzRestMethod -Method GET -Path "/subscriptions/$SubscriptionId/locations?api-version=2022-12-01"
            if ($response.StatusCode -eq 200) {
                $locations = ($response.Content | ConvertFrom-Json).value
                foreach ($loc in $locations) {
                    if ($loc.PSObject.Properties['availabilityZoneMappings'] -and $null -ne $loc.availabilityZoneMappings) {
                        foreach ($azm in $loc.availabilityZoneMappings) {
                            $key = "$($loc.name)|$($azm.logicalZone)"
                            $mappings[$key] = $azm.physicalZone
                        }
                    }
                }
            }
            else {
                Write-Warning "Failed to get zone mappings for subscription $SubscriptionId (HTTP $($response.StatusCode))"
            }
        }
        catch {
            Write-Warning "Error getting zone mappings for subscription $SubscriptionId : $_"
        }
        return $mappings
    }
    #endregion

    #region --- Subscription name lookup (needed by zone mapping and reports) ---
    $subNameLookup = @{}
    $allSubsToResolveNames = [System.Collections.Generic.List[string]]::new()
    foreach ($sid in $subscriptionIds) { $allSubsToResolveNames.Add($sid) }
    if ($SharedCapacitySubscriptionId -and $allSubsToResolveNames -notcontains $SharedCapacitySubscriptionId) {
        $allSubsToResolveNames.Add($SharedCapacitySubscriptionId)
    }
    foreach ($subId in $allSubsToResolveNames) {
        try {
            $s = Get-AzSubscription -SubscriptionId $subId -ErrorAction SilentlyContinue
            if ($s) { $subNameLookup[$subId] = $s.Name }
            else { $subNameLookup[$subId] = $subId }
        }
        catch { $subNameLookup[$subId] = $subId }
    }
    #endregion

    #region --- Zone Mappings ---
    Write-Host "Collecting availability zone mappings ..." -ForegroundColor Yellow

    # Collect zone mappings for all target subscriptions + shared capacity subscription
    $allSubsForZones = [System.Collections.Generic.List[string]]::new()
    foreach ($sid in $subscriptionIds) { $allSubsForZones.Add($sid) }
    if ($SharedCapacitySubscriptionId -and $allSubsForZones -notcontains $SharedCapacitySubscriptionId) {
        $allSubsForZones.Add($SharedCapacitySubscriptionId)
    }

    # zoneMappingsBySubscription: subscriptionId -> hashtable{ "region|logicalZone" -> physicalZone }
    $zoneMappingsBySubscription = @{}
    $savedContext = Get-AzContext
    foreach ($sid in $allSubsForZones) {
        Write-Verbose "  Getting zone mappings for subscription $sid ..."
        Set-AzContext -SubscriptionId $sid -ErrorAction SilentlyContinue | Out-Null
        $m = Get-ZoneMappings -SubscriptionId $sid
        $zoneMappingsBySubscription[$sid] = $m
        Write-Host "    $($subNameLookup[$sid] ?? $sid): $($m.Count) zone mappings" -ForegroundColor DarkGray
    }
    # Restore original context
    if ($savedContext) {
        Set-AzContext -SubscriptionId $savedContext.Subscription.Id -ErrorAction SilentlyContinue | Out-Null
    }

    # Build a flat zone-mapping table for the Excel sheet
    $zoneMappingRows = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($sid in $allSubsForZones) {
        $subName = $subNameLookup[$sid] ?? $sid
        $mappings = $zoneMappingsBySubscription[$sid]
        if (-not $mappings) { continue }
        foreach ($key in ($mappings.Keys | Sort-Object)) {
            $parts = $key -split '\|'
            $region = $parts[0]
            $logicalZone = $parts[1]
            $physicalZone = $mappings[$key]
            $zoneMappingRows.Add([PSCustomObject]@{
                Subscription   = $subName
                SubscriptionId = $sid
                Region         = $region
                LogicalZone    = $logicalZone
                PhysicalZone   = $physicalZone
            })
        }
    }
    Write-Host "  Collected zone mappings for $($allSubsForZones.Count) subscriptions" -ForegroundColor Green

    # Helper function: resolve logical zone to physical zone for a given subscription + region
    function Resolve-PhysicalZone {
        param(
            [string]$SubscriptionId,
            [string]$Region,
            [string]$LogicalZone
        )
        if (-not $LogicalZone -or $LogicalZone -eq '' -or $LogicalZone -eq '[]') { return 'no-zone' }
        $mappings = $zoneMappingsBySubscription[$SubscriptionId]
        if (-not $mappings) { return "unknown($LogicalZone)" }
        $key = "$Region|$LogicalZone"
        $physical = $mappings[$key]
        if ($physical) { return $physical }
        return "unmapped($LogicalZone)"
    }
    #endregion

    #region --- 1. Collect VMs ---
    Write-Host "Querying VMs ..." -ForegroundColor Yellow
    $vmQuery = @"
resources
| where type == "microsoft.compute/virtualmachines"
| extend vmSize = tostring(properties.hardwareProfile.vmSize),
         powerState = tostring(properties.extended.instanceView.powerState.displayStatus),
         osType = tostring(properties.storageProfile.osDisk.osType),
         capacityReservationGroupId = tolower(tostring(properties.capacityReservation.capacityReservationGroup.id)),
         zones = tostring(properties.zones)
| project id, name, subscriptionId, resourceGroup, location, vmSize, powerState, osType, zones, capacityReservationGroupId, tags
"@
    $vms = @(Invoke-ResourceGraphQuery -Query $vmQuery -SubscriptionIds $subscriptionIds)
    Write-Host "  Found $($vms.Count) VMs" -ForegroundColor Green
    #endregion

    #region --- 2. Collect ASR replicated items ---
    Write-Host "Querying Site Recovery replicated items ..." -ForegroundColor Yellow
    $asrQuery = @"
recoveryservicesresources
| where type == "microsoft.recoveryservices/vaults/replicationfabrics/replicationprotectioncontainers/replicationprotecteditems"
| extend sourceVmId = tolower(tostring(properties.providerSpecificDetails.fabricObjectId)),
         replicationHealth = tostring(properties.replicationHealth),
         protectionState = tostring(properties.protectionState),
         activeLocation = tostring(properties.activeLocation),
         policyFriendlyName = tostring(properties.policyFriendlyName),
         testFailoverState = tostring(properties.testFailoverState),
         lastSuccessfulTestFailover = tostring(properties.lastSuccessfulTestFailoverTime)
| project sourceVmId, name, replicationHealth, protectionState, activeLocation, policyFriendlyName, testFailoverState, lastSuccessfulTestFailover, subscriptionId
"@
    $asrItems = @(Invoke-ResourceGraphQuery -Query $asrQuery -SubscriptionIds $subscriptionIds)
    Write-Host "  Found $($asrItems.Count) ASR replicated items" -ForegroundColor Green

    # Build lookup: VM resource ID -> ASR info
    $asrLookup = @{}
    foreach ($item in $asrItems) {
        if ($item.sourceVmId) {
            $asrLookup[$item.sourceVmId] = $item
        }
    }
    #endregion

    #region --- 3. Collect Capacity Reservation Groups (local + shared) ---
    Write-Host "Querying Capacity Reservation Groups ..." -ForegroundColor Yellow

    # Local CRGs (owned by the target subscriptions)
    $crgQuery = @"
resources
| where type == "microsoft.compute/capacityreservationgroups"
| extend sharingProfile = tostring(properties.sharingProfile),
         zones = tostring(zones)
| project id, name, subscriptionId, resourceGroup, location, zones, sharingProfile, tags
"@
    $crgs = @(Invoke-ResourceGraphQuery -Query $crgQuery -SubscriptionIds $subscriptionIds)
    Write-Host "  Found $($crgs.Count) local CRGs" -ForegroundColor Green

    # Shared CRGs (owned by other subscriptions but shared TO target subscriptions)
    $sharedCrgs = @()
    if ($IncludeSharedCapacityReservations -or $SharedCapacitySubscriptionId) {
        Write-Host "Querying shared Capacity Reservation Groups ..." -ForegroundColor Yellow

        # If SharedCapacitySubscriptionId is specified, query CRGs directly from that subscription
        if ($SharedCapacitySubscriptionId) {
            $sharedFromSub = @(Invoke-ResourceGraphQuery -Query $crgQuery -SubscriptionIds @($SharedCapacitySubscriptionId))
            foreach ($s in $sharedFromSub) {
                # Only include if not already in local CRGs
                if (-not ($crgs | Where-Object { $_.id -eq $s.id })) {
                    $sharedCrgs += $s
                }
            }
        }

        # Also do the discovery query for CRGs shared to our subscriptions
        if ($IncludeSharedCapacityReservations) {
            foreach ($subId in $subscriptionIds) {
                $sharedCrgQuery = @"
resources
| where type == "microsoft.compute/capacityreservationgroups"
| where tostring(properties.sharingProfile) contains "$subId"
| where subscriptionId != "$subId"
| extend sharingProfile = tostring(properties.sharingProfile),
         zones = tostring(zones)
| project id, name, subscriptionId, resourceGroup, location, zones, sharingProfile, tags
"@
                try {
                    $shared = Search-AzGraph -Query $sharedCrgQuery -First 1000
                    if ($shared) { $sharedCrgs += $shared }
                }
                catch {
                    Write-Verbose "Could not query shared CRGs for subscription $subId : $_"
                }
            }
        }
        # Deduplicate
        if ($sharedCrgs.Count -gt 0) {
            $sharedCrgs = @($sharedCrgs | Sort-Object -Property id -Unique)
        } else {
            $sharedCrgs = @()
        }
        Write-Host "  Found $(@($sharedCrgs).Count) shared CRGs from other subscriptions" -ForegroundColor Green
    }

    $allCrgs = [System.Collections.Generic.List[object]]::new()
    foreach ($c in $crgs) { $allCrgs.Add($c) }
    foreach ($c in $sharedCrgs) { $allCrgs.Add($c) }
    # Build CRG lookup by lowercase id
    $crgLookup = @{}
    foreach ($crg in $allCrgs) {
        if ($null -eq $crg -or -not $crg.PSObject.Properties['id']) { continue }
        $crgLookup[$crg.id.ToLower()] = $crg
    }
    #endregion

    #region --- 4. Collect Capacity Reservations (children of CRGs) ---
    Write-Host "Querying Capacity Reservations ..." -ForegroundColor Yellow

    # Collect CRG subscription IDs (may include subscriptions outside our target list for shared CRGs)
    $crgSubIds = [System.Collections.Generic.List[string]]::new()
    foreach ($c in $allCrgs) { if ($crgSubIds -notcontains $c.subscriptionId) { $crgSubIds.Add($c.subscriptionId) } }
    if ($SharedCapacitySubscriptionId -and $crgSubIds -notcontains $SharedCapacitySubscriptionId) {
        $crgSubIds.Add($SharedCapacitySubscriptionId)
    }
    if ($crgSubIds.Count -gt 0) {
        $crQuery = @"
resources
| where type == "microsoft.compute/capacityreservationgroups/capacityreservations"
| extend skuName = tostring(sku.name),
         skuCapacity = toint(sku.capacity),
         provisioningState = tostring(properties.provisioningState),
         reservationId = tostring(properties.reservationId),
         virtualMachinesAssociated = properties.virtualMachinesAssociated,
         zones = tostring(zones),
         parentGroupId = tolower(tostring(split(id, '/capacityReservations/')[0]))
| project id, name, subscriptionId, resourceGroup, location, skuName, skuCapacity,
          provisioningState, virtualMachinesAssociated, zones, parentGroupId, tags
"@
        $crs = @(Invoke-ResourceGraphQuery -Query $crQuery -SubscriptionIds $crgSubIds)
    }
    else {
        $crs = @()
    }
    Write-Host "  Found $($crs.Count) Capacity Reservations" -ForegroundColor Green
    #endregion

    #region --- 5. Build enriched data ---
    Write-Host "Building report data ..." -ForegroundColor Yellow

    # ---- VM sheet ----
    $vmRows = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($vm in $vms) {
        $vmIdLower = $vm.id.ToLower()
        $asr = $asrLookup.ContainsKey($vmIdLower) ? $asrLookup[$vmIdLower] : $null
        $hasDR = [bool]$asr
        $crgName = ''
        $crgShared = ''
        if ($vm.capacityReservationGroupId) {
            $crgObj = $crgLookup.ContainsKey($vm.capacityReservationGroupId) ? $crgLookup[$vm.capacityReservationGroupId] : $null
            $crgName = if ($crgObj) { $crgObj.name } else { $vm.capacityReservationGroupId }
            $crgShared = if ($crgObj -and $crgObj.subscriptionId -ne $vm.subscriptionId) { 'Yes' } else { 'No' }
        }

        # Parse logical zone from the zones string (e.g. '["1"]' -> '1')
        $logicalZone = ''
        $zonesRaw = $vm.zones
        if ($zonesRaw -and $zonesRaw -ne '' -and $zonesRaw -ne '[]') {
            try {
                $zoneArr = $zonesRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($zoneArr -and $zoneArr.Count -gt 0) { $logicalZone = [string]$zoneArr[0] }
            }
            catch { $logicalZone = $zonesRaw -replace '[\[\]"\s]', '' }
        }

        $physicalZone = Resolve-PhysicalZone -SubscriptionId $vm.subscriptionId -Region $vm.location -LogicalZone $logicalZone

        $vmRows.Add([PSCustomObject]@{
            Subscription            = $subNameLookup[$vm.subscriptionId] ?? $vm.subscriptionId
            SubscriptionId          = $vm.subscriptionId
            VMName                  = $vm.name
            ResourceGroup           = $vm.resourceGroup
            Location                = $vm.location
            VMSize                  = $vm.vmSize
            OSType                  = $vm.osType
            PowerState              = $vm.powerState
            LogicalZone             = $logicalZone
            PhysicalZone            = $physicalZone
            HasDR                   = $hasDR
            ReplicationHealth       = if ($asr) { $asr.replicationHealth } else { '' }
            ProtectionState         = if ($asr) { $asr.protectionState } else { '' }
            TestFailoverState       = if ($asr) { $asr.testFailoverState } else { '' }
            LastTestFailover        = if ($asr) { $asr.lastSuccessfulTestFailover } else { '' }
            CapacityReservationGroup       = $crgName
            CapacityReservationGroupShared = $crgShared
            ResourceId              = $vm.id
        })
    }

    # ---- DR Gaps sheet ----
    $drGapRows = $vmRows | Where-Object { -not $_.HasDR }

    # ---- Capacity Reservations sheet ----
    $crRows = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($cr in $crs) {
        $parentCrg = $crgLookup.ContainsKey($cr.parentGroupId) ? $crgLookup[$cr.parentGroupId] : $null
        $associatedVMs = @()
        if ($cr.virtualMachinesAssociated) {
            $associatedVMs = @($cr.virtualMachinesAssociated | ForEach-Object { $_.id })
        }
        $consumedCount = $associatedVMs.Count
        $provisionedCapacity = [int]$cr.skuCapacity
        $availableCapacity = $provisionedCapacity - $consumedCount

        # Figure out which target subscriptions this CRG is shared to
        $sharedToSubs = ''
        if ($parentCrg -and $parentCrg.sharingProfile) {
            try {
                $sharingObj = $parentCrg.sharingProfile | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($sharingObj.subscriptionIds) {
                    $sharedToSubs = ($sharingObj.subscriptionIds | ForEach-Object { $_.id -replace '.*/subscriptions/', '' }) -join '; '
                }
            }
            catch {
                $sharedToSubs = $parentCrg.sharingProfile
            }
        }

        # Resolve the CR's logical zone to physical zone (using the CRG-owning subscription)
        $crLogicalZone = ''
        $crZonesRaw = $cr.zones
        if ($crZonesRaw -and $crZonesRaw -ne '' -and $crZonesRaw -ne '[]') {
            try {
                $zArr = $crZonesRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($zArr -and $zArr.Count -gt 0) { $crLogicalZone = [string]$zArr[0] }
            }
            catch { $crLogicalZone = $crZonesRaw -replace '[\[\]"\s]', '' }
        }
        $crOwnerSub = if ($parentCrg) { $parentCrg.subscriptionId } else { $cr.subscriptionId }
        $crRegion = if ($parentCrg) { $parentCrg.location } else { $cr.location }
        $crPhysicalZone = Resolve-PhysicalZone -SubscriptionId $crOwnerSub -Region $crRegion -LogicalZone $crLogicalZone

        $crRows.Add([PSCustomObject]@{
            CRGName                  = if ($parentCrg) { $parentCrg.name } else { $cr.parentGroupId }
            CRGSubscription          = if ($parentCrg) { $subNameLookup[$parentCrg.subscriptionId] ?? $parentCrg.subscriptionId } else { '' }
            CRGSubscriptionId        = if ($parentCrg) { $parentCrg.subscriptionId } else { '' }
            CRGLocation              = $crRegion
            SharedToSubscriptions    = $sharedToSubs
            ReservationName          = $cr.name
            VMSize                   = $cr.skuName
            ProvisionedCapacity      = $provisionedCapacity
            ConsumedVMs              = $consumedCount
            AvailableCapacity        = $availableCapacity
            UtilisationPct           = if ($provisionedCapacity -gt 0) { [math]::Round(($consumedCount / $provisionedCapacity) * 100, 1) } else { 0 }
            ProvisioningState        = $cr.provisioningState
            LogicalZone              = $crLogicalZone
            PhysicalZone             = $crPhysicalZone
            AssociatedVMIds          = ($associatedVMs -join '; ')
            ReservationResourceId    = $cr.id
            CRGResourceId            = if ($parentCrg) { $parentCrg.id } else { $cr.parentGroupId }
        })
    }

    # ---- Capacity Recommendations ----
    # Compare VM demand (grouped by VMSize + Region + PhysicalZone) vs reserved capacity
    Write-Host "Building capacity recommendations ..." -ForegroundColor Yellow

    # 1. Aggregate VM demand: how many VMs of each SKU in each region+physicalZone
    $vmDemand = @{}  # key: "region|vmSize|physicalZone" -> count
    foreach ($vmRow in $vmRows) {
        $key = "$($vmRow.Location)|$($vmRow.VMSize)|$($vmRow.PhysicalZone)"
        if ($vmDemand.ContainsKey($key)) { $vmDemand[$key]++ }
        else { $vmDemand[$key] = 1 }
    }

    # 2. Aggregate reserved capacity: how many slots of each SKU in each region+physicalZone
    $reservedCapacity = @{}  # key: "region|vmSize|physicalZone" -> total provisioned
    $reservedConsumed = @{}   # key: "region|vmSize|physicalZone" -> total consumed
    foreach ($crRow in $crRows) {
        $key = "$($crRow.CRGLocation)|$($crRow.VMSize)|$($crRow.PhysicalZone)"
        if ($reservedCapacity.ContainsKey($key)) {
            $reservedCapacity[$key] += [int]$crRow.ProvisionedCapacity
            $reservedConsumed[$key] += [int]$crRow.ConsumedVMs
        }
        else {
            $reservedCapacity[$key] = [int]$crRow.ProvisionedCapacity
            $reservedConsumed[$key] = [int]$crRow.ConsumedVMs
        }
    }

    # 3. Merge all keys to produce the recommendation rows
    $allKeys = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($k in $vmDemand.Keys) { [void]$allKeys.Add($k) }
    foreach ($k in $reservedCapacity.Keys) { [void]$allKeys.Add($k) }

    $recoRows = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($key in ($allKeys | Sort-Object)) {
        $parts = $key -split '\|'
        $region = $parts[0]
        $vmSize = $parts[1]
        $physZone = $parts[2]
        $demand = if ($vmDemand.ContainsKey($key)) { $vmDemand[$key] } else { 0 }
        $reserved = if ($reservedCapacity.ContainsKey($key)) { $reservedCapacity[$key] } else { 0 }
        $consumed = if ($reservedConsumed.ContainsKey($key)) { $reservedConsumed[$key] } else { 0 }
        $gap = $demand - $reserved
        $status = if ($gap -gt 0) { "UNDER-RESERVED (need +$gap)" }
                  elseif ($gap -lt 0) { "OVER-RESERVED (excess $([math]::Abs($gap)))" }
                  else { "OK" }

        $recoRows.Add([PSCustomObject]@{
            Region              = $region
            VMSize              = $vmSize
            PhysicalZone        = $physZone
            VMsDeployed         = $demand
            ReservedCapacity    = $reserved
            ConsumedReservations = $consumed
            AvailableReservations = $reserved - $consumed
            Gap                 = $gap
            Status              = $status
            Recommendation      = if ($gap -gt 0) {
                "Add $gap x $vmSize capacity reservation in $region / $physZone"
            } elseif ($gap -lt 0) {
                "$([math]::Abs($gap)) excess $vmSize reservations in $region / $physZone could be reduced"
            } else {
                "Capacity matches demand"
            }
        })
    }

    # ---- Subscription Summary sheet ----
    $summaryRows = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($subId in $subscriptionIds) {
        $subVMs = $vmRows | Where-Object { $_.SubscriptionId -eq $subId }
        $totalVMs = ($subVMs | Measure-Object).Count
        $drProtected = ($subVMs | Where-Object { $_.HasDR } | Measure-Object).Count
        $drGaps = $totalVMs - $drProtected
        $withCR = ($subVMs | Where-Object { $_.CapacityReservationGroup -ne '' } | Measure-Object).Count
        $localCRGs = ($crgs | Where-Object { $_.subscriptionId -eq $subId } | Measure-Object).Count
        $sharedToThis = ($sharedCrgs | Where-Object {
            $_.sharingProfile -and $_.sharingProfile -match $subId
        } | Measure-Object).Count

        # Capacity reservation totals for CRGs owned by this subscription
        $subCRs = @($crRows | Where-Object { $_.CRGSubscriptionId -eq $subId })
        $totalProvisioned = 0
        $totalConsumed = 0
        foreach ($cr in $subCRs) {
            $totalProvisioned += [int]$cr.ProvisionedCapacity
            $totalConsumed += [int]$cr.ConsumedVMs
        }

        $summaryRows.Add([PSCustomObject]@{
            Subscription                = $subNameLookup[$subId] ?? $subId
            SubscriptionId              = $subId
            TotalVMs                    = $totalVMs
            DRProtectedVMs              = $drProtected
            DRGapVMs                    = $drGaps
            DRCoveragePct               = if ($totalVMs -gt 0) { [math]::Round(($drProtected / $totalVMs) * 100, 1) } else { 0 }
            VMsWithCapacityReservation  = $withCR
            LocalCRGs                   = $localCRGs
            SharedCRGsToThisSub         = $sharedToThis
            TotalProvisionedCapacity    = [int]$totalProvisioned
            TotalConsumedCapacity       = [int]$totalConsumed
            AvailableCapacity           = [int]$totalProvisioned - [int]$totalConsumed
        })
    }
    #endregion

    #region --- 6. Export to Excel ---
    Write-Host "Exporting to $ExcelFile ..." -ForegroundColor Yellow

    # Remove existing file to avoid sheet duplication
    if (Test-Path $ExcelFile) { Remove-Item $ExcelFile -Force }

    # ===== Summary (Dashboard) sheet — created first so it's the first tab =====
    # Create a blank workbook by exporting a placeholder, then remove the placeholder
    [PSCustomObject]@{ _placeholder = '' } | Export-Excel -Path $ExcelFile -WorksheetName '_tmp' -AutoSize
    $pkg = Open-ExcelPackage -Path $ExcelFile
    $ws = $pkg.Workbook.Worksheets.Add('Summary')
    $pkg.Workbook.Worksheets.MoveToStart('Summary')
    $pkg.Workbook.Worksheets.Delete('_tmp')

    # --- KPI header row ---
    $totalVMsAll = ($vmRows | Measure-Object).Count
    $drProtectedAll = ($vmRows | Where-Object { $_.HasDR } | Measure-Object).Count
    $drGapAll = $totalVMsAll - $drProtectedAll
    $drPctAll = if ($totalVMsAll -gt 0) { [math]::Round(($drProtectedAll / $totalVMsAll) * 100, 1) } else { 0 }
    $underReservedCount = ($recoRows | Where-Object { $_.Gap -gt 0 } | Measure-Object).Count
    $okCount = ($recoRows | Where-Object { $_.Gap -eq 0 } | Measure-Object).Count
    $overReservedCount = ($recoRows | Where-Object { $_.Gap -lt 0 } | Measure-Object).Count

    # Helper: column letter from 1-based index
    function ColLetter([int]$c) {
        if ($c -le 26) { return [char](64 + $c) }
        return [char](64 + [math]::Floor(($c - 1) / 26)) + [char](65 + (($c - 1) % 26))
    }
    # Helper: set cell value + optional styling via string address
    function Set-Cell {
        param($ws, [int]$Row, [int]$Col, $Value, [switch]$Bold, [int]$FontSize = 0,
              [System.Drawing.Color]$FontColor, [System.Drawing.Color]$BgColor,
              [switch]$Center)
        $addr = "$(ColLetter $Col)$Row"
        $ws.Cells[$addr].Value = $Value
        if ($Bold) { $ws.Cells[$addr].Style.Font.Bold = $true }
        if ($FontSize -gt 0) { $ws.Cells[$addr].Style.Font.Size = $FontSize }
        if ($null -ne $FontColor -and $FontColor.A -ne 0) { $ws.Cells[$addr].Style.Font.Color.SetColor($FontColor) }
        if ($null -ne $BgColor -and $BgColor.A -ne 0) {
            $ws.Cells[$addr].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            $ws.Cells[$addr].Style.Fill.BackgroundColor.SetColor($BgColor)
        }
        if ($Center) { $ws.Cells[$addr].Style.HorizontalAlignment = [OfficeOpenXml.Style.ExcelHorizontalAlignment]::Center }
    }

    # Title
    $ws.Cells["A1"].Value = "Resiliency Report — Summary Dashboard"
    $ws.Cells["A1"].Style.Font.Size = 16
    $ws.Cells["A1"].Style.Font.Bold = $true
    $ws.Cells["A1:F1"].Merge = $true

    $ws.Cells["A2"].Value = "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $ws.Cells["A2"].Style.Font.Color.SetColor([System.Drawing.Color]::Gray)
    $ws.Cells["A2:F2"].Merge = $true

    # KPI boxes row 4
    $kpiHeaders = @('Total VMs', 'DR Protected', 'DR Gaps', 'DR Coverage %', 'Under-Reserved SKUs', 'Over-Reserved SKUs')
    $kpiValues  = @($totalVMsAll, $drProtectedAll, $drGapAll, $drPctAll, $underReservedCount, $overReservedCount)
    $kpiColors  = @(
        [System.Drawing.Color]::FromArgb(68, 114, 196),   # blue
        [System.Drawing.Color]::FromArgb(0, 128, 0),      # green
        [System.Drawing.Color]::FromArgb(192, 0, 0),      # red
        [System.Drawing.Color]::FromArgb(68, 114, 196),   # blue
        [System.Drawing.Color]::FromArgb(192, 0, 0),      # red
        [System.Drawing.Color]::FromArgb(191, 144, 0)     # amber
    )
    for ($i = 0; $i -lt $kpiHeaders.Count; $i++) {
        $col = $i + 1
        Set-Cell $ws 4 $col $kpiHeaders[$i] -Bold -FontColor ([System.Drawing.Color]::White) -BgColor $kpiColors[$i] -Center
        Set-Cell $ws 5 $col $kpiValues[$i] -Bold -FontSize 18 -Center
    }

    # --- Chart 1: DR Coverage by Subscription (stacked bar) ---
    # Write data table starting at row 8 for the chart source
    $dataStartRow = 8
    Set-Cell $ws $dataStartRow 1 'Subscription' -Bold
    Set-Cell $ws $dataStartRow 2 'DR Protected' -Bold
    Set-Cell $ws $dataStartRow 3 'DR Gaps' -Bold
    $r = $dataStartRow + 1
    foreach ($row in $summaryRows) {
        Set-Cell $ws $r 1 $row.Subscription
        Set-Cell $ws $r 2 ([int]$row.DRProtectedVMs)
        Set-Cell $ws $r 3 ([int]$row.DRGapVMs)
        $r++
    }
    $dataEndRow = $r - 1

    if ($summaryRows.Count -gt 0) {
        $chart1 = $ws.Drawings.AddChart('DRCoverageBySubscription', [OfficeOpenXml.Drawing.Chart.eChartType]::ColumnStacked)
        $chart1.Title.Text = 'DR Coverage by Subscription'
        $chart1.SetPosition(6, 0, 4, 0)   # row 7, col E
        $chart1.SetSize(550, 320)
        $chart1.Legend.Position = [OfficeOpenXml.Drawing.Chart.eLegendPosition]::Bottom

        $labelsRange = "Summary!A$($dataStartRow + 1):A$dataEndRow"
        $series1 = $chart1.Series.Add("Summary!B$($dataStartRow + 1):B$dataEndRow", $labelsRange)
        $series1.Header = 'DR Protected'
        $series1.Fill.Color = [System.Drawing.Color]::FromArgb(0, 176, 80)

        $series2 = $chart1.Series.Add("Summary!C$($dataStartRow + 1):C$dataEndRow", $labelsRange)
        $series2.Header = 'DR Gaps'
        $series2.Fill.Color = [System.Drawing.Color]::FromArgb(255, 0, 0)
    }

    # --- Chart 2: Overall DR Coverage (pie chart) ---
    # Data at a hidden area
    $pieDataRow = $dataEndRow + 2
    Set-Cell $ws $pieDataRow 1 'Category' -Bold
    Set-Cell $ws $pieDataRow 2 'Count' -Bold
    $pd1 = $pieDataRow + 1
    $pd2 = $pieDataRow + 2
    Set-Cell $ws $pd1 1 'DR Protected'
    Set-Cell $ws $pd1 2 $drProtectedAll
    Set-Cell $ws $pd2 1 'DR Gaps'
    Set-Cell $ws $pd2 2 $drGapAll

    if ($totalVMsAll -gt 0) {
        $chart2 = $ws.Drawings.AddChart('OverallDRCoverage', [OfficeOpenXml.Drawing.Chart.eChartType]::Pie)
        $chart2.Title.Text = 'Overall DR Coverage'
        $chart2.SetPosition(6, 0, 13, 0)   # row 7, col N
        $chart2.SetSize(380, 320)
        $chart2.Legend.Position = [OfficeOpenXml.Drawing.Chart.eLegendPosition]::Bottom

        $pieSeries = $chart2.Series.Add("Summary!B${pd1}:B${pd2}", "Summary!A${pd1}:A${pd2}")
        $pieSeries.Header = 'VMs'
    }

    # --- Chart 3: Capacity Demand vs Reserved (clustered bar per SKU/region/zone) ---
    if ($recoRows.Count -gt 0) {
        $capDataRow = $pieDataRow + 4
        Set-Cell $ws $capDataRow 1 'SKU / Region / Zone' -Bold
        Set-Cell $ws $capDataRow 2 'VMs Deployed' -Bold
        Set-Cell $ws $capDataRow 3 'Reserved Capacity' -Bold
        $cr2 = $capDataRow + 1
        foreach ($reco in $recoRows) {
            $label = "$($reco.VMSize) / $($reco.Region) / $($reco.PhysicalZone)"
            Set-Cell $ws $cr2 1 $label
            Set-Cell $ws $cr2 2 ([int]$reco.VMsDeployed)
            Set-Cell $ws $cr2 3 ([int]$reco.ReservedCapacity)
            $cr2++
        }
        $capDataEnd = $cr2 - 1

        $chart3 = $ws.Drawings.AddChart('CapacityDemandVsReserved', [OfficeOpenXml.Drawing.Chart.eChartType]::ColumnClustered)
        $chart3.Title.Text = 'Capacity: VM Demand vs Reserved'
        $chart3.SetPosition(24, 0, 0, 0)   # row 25, col A
        $chart3.SetSize(750, 350)
        $chart3.Legend.Position = [OfficeOpenXml.Drawing.Chart.eLegendPosition]::Bottom

        $capLabels = "Summary!A$($capDataRow + 1):A$capDataEnd"
        $s3a = $chart3.Series.Add("Summary!B$($capDataRow + 1):B$capDataEnd", $capLabels)
        $s3a.Header = 'VMs Deployed (Demand)'
        $s3a.Fill.Color = [System.Drawing.Color]::FromArgb(68, 114, 196)

        $s3b = $chart3.Series.Add("Summary!C$($capDataRow + 1):C$capDataEnd", $capLabels)
        $s3b.Header = 'Reserved Capacity'
        $s3b.Fill.Color = [System.Drawing.Color]::FromArgb(0, 176, 80)

        # --- Chart 4: Capacity Gap Status (pie: OK / Under / Over) ---
        $gapPieRow = $capDataEnd + 2
        Set-Cell $ws $gapPieRow 1 'Status' -Bold
        Set-Cell $ws $gapPieRow 2 'Count' -Bold
        $gp1 = $gapPieRow + 1
        $gp2 = $gapPieRow + 2
        $gp3 = $gapPieRow + 3
        Set-Cell $ws $gp1 1 'OK'
        Set-Cell $ws $gp1 2 $okCount
        Set-Cell $ws $gp2 1 'Under-Reserved'
        Set-Cell $ws $gp2 2 $underReservedCount
        Set-Cell $ws $gp3 1 'Over-Reserved'
        Set-Cell $ws $gp3 2 $overReservedCount

        if (($okCount + $underReservedCount + $overReservedCount) -gt 0) {
            $chart4 = $ws.Drawings.AddChart('CapacityGapStatus', [OfficeOpenXml.Drawing.Chart.eChartType]::Pie)
            $chart4.Title.Text = 'Capacity Reservation Status'
            $chart4.SetPosition(24, 0, 12, 0)   # row 25, col M
            $chart4.SetSize(380, 350)
            $chart4.Legend.Position = [OfficeOpenXml.Drawing.Chart.eLegendPosition]::Bottom

            $gapSeries = $chart4.Series.Add("Summary!B${gp1}:B${gp3}", "Summary!A${gp1}:A${gp3}")
            $gapSeries.Header = 'SKU Combinations'
        }
    }

    # Column widths
    1..6 | ForEach-Object { $ws.Column($_).Width = @(35, 18, 18, 22, 22, 22)[$_ - 1] }

    Close-ExcelPackage $pkg

    # SubscriptionSummary sheet
    $summaryRows | Export-Excel -Path $ExcelFile -WorksheetName 'SubscriptionSummary' `
        -AutoSize -FreezeTopRow -BoldTopRow -TableStyle Medium6

    # VMs sheet
    $vmRows | Export-Excel -Path $ExcelFile -WorksheetName 'VMs' `
        -AutoSize -FreezeTopRow -BoldTopRow -TableStyle Medium2

    # CapacityReservations sheet
    if ($crRows.Count -gt 0) {
        $crRows | Export-Excel -Path $ExcelFile -WorksheetName 'CapacityReservations' `
            -AutoSize -FreezeTopRow -BoldTopRow -TableStyle Medium4
    }
    else {
        [PSCustomObject]@{ Info = 'No capacity reservations found in the target subscriptions.' } |
            Export-Excel -Path $ExcelFile -WorksheetName 'CapacityReservations' -AutoSize
    }

    # DRGaps sheet
    if (($drGapRows | Measure-Object).Count -gt 0) {
        $drGapRows | Export-Excel -Path $ExcelFile -WorksheetName 'DRGaps' `
            -AutoSize -FreezeTopRow -BoldTopRow -TableStyle Medium3

        # Add conditional formatting to highlight the DR gaps
        $pkg = Open-ExcelPackage -Path $ExcelFile
        $ws = $pkg.Workbook.Worksheets['DRGaps']
        $lastRow = $ws.Dimension.End.Row
        Add-ConditionalFormatting -Worksheet $ws -Range "K2:K$lastRow" `
            -RuleType Equal -ConditionValue 'FALSE' `
            -BackgroundColor ([System.Drawing.Color]::FromArgb(255, 199, 206)) `
            -ForegroundColor ([System.Drawing.Color]::FromArgb(156, 0, 6))
        Close-ExcelPackage $pkg
    }
    else {
        [PSCustomObject]@{ Info = 'All VMs have Site Recovery replication configured.' } |
            Export-Excel -Path $ExcelFile -WorksheetName 'DRGaps' -AutoSize
    }

    # ZoneMappings sheet
    if ($zoneMappingRows.Count -gt 0) {
        $zoneMappingRows | Export-Excel -Path $ExcelFile -WorksheetName 'ZoneMappings' `
            -AutoSize -FreezeTopRow -BoldTopRow -TableStyle Medium9
    }
    else {
        [PSCustomObject]@{ Info = 'No zone mappings retrieved (subscriptions may not support availability zones).' } |
            Export-Excel -Path $ExcelFile -WorksheetName 'ZoneMappings' -AutoSize
    }

    # CapacityRecommendations sheet
    if ($recoRows.Count -gt 0) {
        $recoRows | Export-Excel -Path $ExcelFile -WorksheetName 'CapacityRecommendations' `
            -AutoSize -FreezeTopRow -BoldTopRow -TableStyle Medium7

        # Highlight under-reserved rows
        $pkg = Open-ExcelPackage -Path $ExcelFile
        $ws = $pkg.Workbook.Worksheets['CapacityRecommendations']
        $lastRow = $ws.Dimension.End.Row
        # Column I = Status
        Add-ConditionalFormatting -Worksheet $ws -Range "I2:I$lastRow" `
            -RuleType ContainsText -ConditionValue 'UNDER-RESERVED' `
            -BackgroundColor ([System.Drawing.Color]::FromArgb(255, 199, 206)) `
            -ForegroundColor ([System.Drawing.Color]::FromArgb(156, 0, 6))
        Add-ConditionalFormatting -Worksheet $ws -Range "I2:I$lastRow" `
            -RuleType ContainsText -ConditionValue 'OVER-RESERVED' `
            -BackgroundColor ([System.Drawing.Color]::FromArgb(255, 235, 156)) `
            -ForegroundColor ([System.Drawing.Color]::FromArgb(156, 101, 0))
        Add-ConditionalFormatting -Worksheet $ws -Range "I2:I$lastRow" `
            -RuleType Equal -ConditionValue 'OK' `
            -BackgroundColor ([System.Drawing.Color]::FromArgb(198, 239, 206)) `
            -ForegroundColor ([System.Drawing.Color]::FromArgb(0, 97, 0))
        Close-ExcelPackage $pkg
    }
    else {
        [PSCustomObject]@{ Info = 'No VMs or capacity reservations found — no recommendations to generate.' } |
            Export-Excel -Path $ExcelFile -WorksheetName 'CapacityRecommendations' -AutoSize
    }
    #endregion

    Write-Host ""
    Write-Host "Report generated: $ExcelFile" -ForegroundColor Green
    Write-Host ""
    Write-Host "Summary:" -ForegroundColor Cyan
    foreach ($row in $summaryRows) {
        Write-Host ("  {0}: {1} VMs, {2} DR-protected ({3}%), {4} CRGs (local), {5} shared CRGs, capacity: {6} provisioned / {7} consumed" -f `
            $row.Subscription, $row.TotalVMs, $row.DRProtectedVMs, $row.DRCoveragePct,
            $row.LocalCRGs, $row.SharedCRGsToThisSub, $row.TotalProvisionedCapacity, $row.TotalConsumedCapacity)
    }
    if ($recoRows.Count -gt 0) {
        $underReserved = @($recoRows | Where-Object { $_.Gap -gt 0 })
        Write-Host ""
        Write-Host "Capacity Recommendations:" -ForegroundColor Cyan
        if ($underReserved.Count -gt 0) {
            Write-Host "  $($underReserved.Count) SKU/region/zone combination(s) are UNDER-RESERVED:" -ForegroundColor Red
            foreach ($r in $underReserved) {
                Write-Host ("    -> {0}" -f $r.Recommendation) -ForegroundColor Red
            }
        }
        else {
            Write-Host "  All SKU/region/zone combinations have sufficient capacity reservations." -ForegroundColor Green
        }
    }
}
