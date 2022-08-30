param(
    [Parameter(Mandatory=$true)]
    [string]$ip
)

class IP {
    [bool[]] hidden $ipbitmask
    [string] hidden $ip

    IP([string]$ip) {
        $this.ip = $ip.Trim()
        $this.ipbitmask = [IP]::GetIPBitMask($this.ip)
    }

    [bool[]] hidden static GetIPBitMask([string]$ip) {
        $bm = new-object bool[] 32

        for($i = 0; $i -lt 32; $i++) {
            $bm[$i] = $false
        }

        $ipa = $ip.Trim().Split('.')
        if($ipa.Count -ne 4) {
            throw "Invalid IP Address: $ip"
        }

        for($i = 0; $i -lt 4; $i++) {
            $seg = [int]$ipa[$i]
            for($ii = 0; $seg -gt 0; $ii++) {
                #Write-Host ("" + (($i * 8) + 8 - $ii - 1) + " "  + ($seg % 2) + "  $seg")
                $bm[($i * 8) + 8 - $ii - 1] = [bool]($seg % 2)
                $seg = [Math]::Floor($seg / 2)
            }

            $s = ""
            for($ii = 0; $ii -lt 8; $ii++) {
                if($bm[($i * 8) + $ii]) {
                    $s += "1"
                }
                else {
                    $s += "0"
                }
            }
            $seg = [int]$ipa[$i]
            #Write-Host "SEG: $seg = $s"
        }
        return $bm
    }

    [string] GetIP() {
        return $this.ip
    }

    [bool[]] GetBitMask() {
        return $this.ipbitmask
    }

    [string] GetBitMaskString() {
        $s = ""
        for($i = 0; $i -lt 32; $i++) {
            if(($i % 8) -eq 0  -and  $i -gt 0) {
                $s += "."
            }
            if($this.ipbitmask[$i]) {
                $s += "1"
            }
            else {
                $s += "0"
            }
        }
        return $s;
    }

    [string] ToString() {
        return ("IP " + $this.ip + " (" + $this.GetBitMaskString() + ")")
    }
}


class Subnet {
    [IP] hidden $ip
    [IP] hidden $mask

    Subnet([string]$subnet) {
        $parts = $subnet -split "/"
        if($parts.Count -ne 2) {
            throw "Invalid subnet"
        }
        $this.ip = [IP]::new($parts[0])

        if($parts[1] -match '\d+' ) {
            $this.mask = [Subnet]::GetMaskIPFromCIDR($parts[1])
        }
        else {
            $this.mask = [IP]::new($parts[1])
        }
    }

    [IP] hidden static  GetMaskIPFromCIDR($int) {
        $bm = new-object bool[] 32

        for($i = 0; $i -lt 32; $i++) {
            $bm[$i] = $false
        }

        for($i = 0; $i -lt $int; $i++) {
            $bm[$i] = $true
        }

        return  [IP]::new([Subnet]::GetIPFromBitmask($bm))
    }

    [string] hidden static GetIPFromBitmask([bool[]] $bm) {
        $a=@()
        for($i = 0; $i -lt 4; $i++) {
            $d = 0;
            for($ii = 0; $ii -lt 8; $ii++) {
                if($bm[($i*8) + $ii]) {
                    $d += [Math]::pow(2, 8 - $ii - 1)
                }
            }
            $a += $d
        }
        return ($a -join ".")
    }

    [string] ToString() {
        return ( $this.ip.GetIP() + " / " + $this.mask.GetIP())
    }

    [IP] GetFirstIP() {
        $bm = new-object bool[] 32

        $ipbm = $this.ip.GetBitMask()
        $maskbm = $this.mask.GetBitMask()

        for($i = 0; $i -lt 32; $i++) {
            if($maskbm[$i]) {
                $bm[$i] = $ipbm[$i]
            }
            else {
                $bm[$i] = $false
            }
        }

        return [IP]::new([Subnet]::GetIPFromBitmask($bm))
    }

    [IP] GetLastIP() {
        $bm = new-object bool[] 32

        $ipbm = $this.ip.GetBitMask()
        $maskbm = $this.mask.GetBitMask()

        for($i = 0; $i -lt 32; $i++) {
            if($maskbm[$i]) {
                $bm[$i] = $ipbm[$i]
            }
            else {
                $bm[$i] = $true
            }
        }

        return [IP]::new([Subnet]::GetIPFromBitmask($bm))
    }

    [bool] ContainsIP([string]$ip) {
        return $this.ContainsIP([IP]::new($ip))
    }

    [bool] ContainsIP([IP]$ip) {
        $bm = $ip.GetBitMask()
        $ipbm = $this.ip.GetBitMask()
        $maskbm = $this.mask.GetBitMask()

        for($i = 0; $i -lt 32; $i++) {
            if($maskbm[$i]) {
                if($bm[$i] -ne $ipbm[$i]) {
                    return $false
                }
            }
        }


        return $true
    }

}


$ipToCheck = [IP]::new($ip)

$found = $false
foreach($l in Get-AzLocation) {
    foreach($z in Get-AzNetworkServiceTag -Location $l.Location) {
        foreach($v in $z.Values) {
            foreach($p in $v.properties.addressPrefixes) {
                try {
                    $subnet = [Subnet]::new($p)
                    if($subnet.ContainsIP($ipToCheck)) {
                        $s = "$p"
                        if($v.name) {
                            $s += ("`n`tName = " + $v.name)
                        }
                        if($v.properties.region) {
                            $s += ("`n`tRegion = " + $v.properties.region)
                        }
                        if($v.properties.platform) {
                            $s += ("`n`tPlatform = " + $v.properties.platform)
                        }
                        if($v.properties.systemService) {
                            $s += ("`n`tService = " + $v.properties.systemService)
                        }
    
                        Write-Host "HIT: $s"

                        $found = $true
                    }
                }
                catch {
    
                }
            }
        }
    }
    if($found) {
        break
    }
}
