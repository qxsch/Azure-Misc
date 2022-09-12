param(
    [Parameter(Mandatory=$true)]
    [string]$ip
)

class IP {
    [bool[]] hidden $ipbitmask
    [string] hidden $ip

    IP([string]$ip) {
        $this.ip = $ip.Trim()
        if($this.ip.Contains(".")) {
            $this.ipbitmask = [IP]::GetIP32BitMask($this.ip)    
        }
        elseif($this.ip.Contains(":")) {
            $this.ip = $this.ip.ToUpper()
            $this.ipbitmask = [IP]::GetIP128BitMask($this.ip)    
        }
        else {
            throw "Invalid IP Address: $ip"
        }

    }

    [string[]] hidden static GetIPv6Segments([string]$ip) {
        $ipa = $ip.Trim().Split(':')
        if($ipa.Count -ne 8) {
            $ipa = $ip.Trim().Split('::')
            if($ipa.Count -ne 2) {
                throw "Invalid IP Address: $ip"
            }
            
            $ipa1 = $ipa[0].Split(':')
            $ipa2 = $ipa[1].Split(':')
            $ipa = @()
            foreach($i in $ipa1) {
                if($i -eq "") {
                    $i = "0"
                }
                $ipa += $i
            }
            for($i = 0; $i -lt (8 - ($ipa1.Count + $ipa2.Count)); $i++) {
                $ipa += "0"
            }
            foreach($i in $ipa2) {
                if($i -eq "") {
                    $i = "0"
                }
                $ipa += $i
            }

            if($ipa.Count -ne 8) {
                throw "Invalid IP Address: $ip"
            }
        }
        return $ipa
    }

    [bool[]] hidden static GetIP128BitMask([string]$ip) {
        $bm = new-object bool[] 128

        for($i = 0; $i -lt 128; $i++) {
            $bm[$i] = $false
        }

        $ipa = [IP]::GetIPv6Segments($ip)

        for($i = 0; $i -lt 8; $i++) {
            if($ipa[$i] -eq "") {
                continue
            }
            $seg =  [Convert]::ToInt32($ipa[$i], 16)

            for($ii = 0; $seg -gt 0; $ii++) {
                $bm[($i * 16) + 16 - $ii - 1] = [bool]($seg % 2)
                $seg = [Math]::Floor($seg / 2)
            }

            $s = ""
            for($ii = 0; $ii -lt 16; $ii++) {
                if($bm[($i * 16) + $ii]) {
                    $s += "1"
                }
                else {
                    $s += "0"
                }
            }
        }

        return $bm
    }

    [bool[]] hidden static GetIP32BitMask([string]$ip) {
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
        if($this.ipbitmask.Count -eq 32) {
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
            return $s
        }
        elseif($this.ipbitmask.Count -eq 128) {
            $s = ""
            for($i = 0; $i -lt 128; $i++) {
                if(($i % 16) -eq 0  -and  $i -gt 0) {
                    $s += ":"
                }
                if($this.ipbitmask[$i]) {
                    $s += "1"
                }
                else {
                    $s += "0"
                }
            }
            return $s
        }
        else {
            return ""
        }
    }

    [bool] IsIPv4() {
        return $this.ipbitmask.Count -eq 32
    }

    [bool] IsIPv6() {
        return $this.ipbitmask.Count -eq 128
    }

    [bool] BelongsToSubnet([string]$subnet) {
        return ([Subnet]::new($subnet)).ContainsIP($this)
    }

    [bool] BelongsToSubnet([Subnet]$subnet) {
        return $subnet.ContainsIP($this)
    }

    [string] ToString() {
        return ( "" + $this.ip )
    }

    [IP] ConvertToIPv6() {
        if($this.IsIPv6()) {
            return $this
        }
        
        if($this.IsIPv4()) {
            $ipstr = "::FFFF"
            $i = 0
            foreach($p in $this.ip.Split(".")) {
                if(($i % 2) -eq 0) {
                    $ipstr += ":"
                }
                $s = ([int]$p).ToString("X")
                if($s.Length -lt 2) {
                    $s = "0$s"
                }
                $ipstr += "$s"
                $i++
            }
            return [IP]::new($ipstr.ToUpper())
        }

        throw "IP cannot be converted to version 6"
    }
}


class Subnet {
    [IP] hidden $ip
    [IP] hidden $mask
    [int] hidden $cidr

    Subnet([string]$subnet) {
        $parts = $subnet -split "/"
        if($parts.Count -ne 2) {
            throw "Invalid subnet: $subnet"
        }
        $parts[0] = $parts[0].Trim()
        $parts[1] = $parts[1].Trim()
        $this.ip = [IP]::new($parts[0])

        if($parts[1] -match '^\d+$' ) {
            $this.cidr = ([int]$parts[1])
            $this.mask = [Subnet]::GetMaskIPFromCIDR($parts[1], $this.ip.GetBitMask().Count)
        }
        else {
            $this.cidr = -1
            $this.mask = [IP]::new($parts[1])
        }
        if($this.ip.IsIPv4() -and (-not $this.mask.IsIPv4())) {
            throw "Invalid subnet: $subnet"
        }
        if($this.ip.IsIPv6() -and (-not $this.mask.IsIPv6())) {
            throw "Invalid subnet: $subnet"
        }
    }

    [IP] hidden static  GetMaskIPFromCIDR([int]$int, [int]$len) {
        $bm = new-object bool[] $len

        for($i = 0; $i -lt $len; $i++) {
            $bm[$i] = $false
        }

        for($i = 0; $i -lt $int; $i++) {
            $bm[$i] = $true
        }

        return  [IP]::new([Subnet]::GetIPFromBitmask($bm))
    }

    [string] hidden static GetIPFromBitmask([bool[]] $bm) {
        if($bm.Count -eq 32) {
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
        elseif($bm.Count -eq 128) {
            $s = ""
            for($i = 0; $i -lt 32; $i++) {
                if(($i % 4) -eq 0  -and  $i -gt 0) {
                    $s+=":"
                }

                $d = 0
                for($ii = 0; $ii -lt 4 ; $ii++) {
                    if($bm[($i * 4) + $ii]) {
                        $d += [Math]::pow(2, 4 - $ii -1)
                    }
                }
                $s += ([int]$d).ToString("X")
            }
            # removed unwanted zeros
            $a = $s -split ":"
            for($i=0 ; $i -lt 8; $i++) {
                while($a[$i][0] -eq "0"  -and  $a[$i] -ne "0") {
                    $a[$i] = $a[$i].Substring(1)
                }
            }
            return ($a -join ":")
        }
        else {
            return ""
        }
    }

    [string] ToString() {
        if($this.cidr -ne -1) {
            return ( $this.ip.GetIP() + " / " + $this.cidr)
        }
        return ( $this.ip.GetIP() + " / " + $this.mask.GetIP())
    }

    [IP] GetSubnetIP() {
        return $this.ip
    }

    [IP] GetSubnetMask() {
        return $this.mask
    }

    [IP] GetFirstIP() {
        $ipbm = $this.ip.GetBitMask()
        $maskbm = $this.mask.GetBitMask()

        $len = $ipbm.Count
        $bm = new-object bool[] $len

        for($i = 0; $i -lt $len; $i++) {
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
        $ipbm = $this.ip.GetBitMask()
        $maskbm = $this.mask.GetBitMask()

        $len = $ipbm.Count
        $bm = new-object bool[] $len

        for($i = 0; $i -lt $len; $i++) {
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

        $len = $ipbm.Count

        # different ip versions? return false
        if($bm.Count -ne $len) {
            return $false
        }

        for($i = 0; $i -lt $len; $i++) {
            if($maskbm[$i]) {
                if($bm[$i] -ne $ipbm[$i]) {
                    return $false
                }
            }
        }


        return $true
    }

    [bool] IsIPv4() {
        return $this.ip.GetBitMask().Count -eq 32
    }

    [bool] IsIPv6() {
        return $this.ip.GetBitMask().Count -eq 128
    }

    [Subnet] ConvertToIPv6() {
        if($this.IsIPv6()) {
            return $this
        }
        
        if($this.IsIPv4()) {
            if($this.cidr -ne -1) {
                return [Subnet]::new($this.ip.ConvertToIPv6().GetIP() + "/" + ($this.cidr + 96))
            }

            $bm = new-object bool[] 128
            for($i = 0; $i -lt 96; $i++) {
                $bm[$i] = $true
            }
    
            $bmm = $this.mask.GetBitMask()
            for($i = 0; $i -lt 32; $i++) {
                $bm[$i + 96] = $bmm[$i]
            }

            return [Subnet]::new($this.ip.ConvertToIPv6().GetIP() + "/" + [Subnet]::GetIPFromBitmask($bm))
        }

        throw "IP cannot be converted to version 6" 
    }
}


$ipToCheck = [IP]::new($ip)

$isipv4 = $ipToCheck.IsIPv4()
$isipv6 = $ipToCheck.IsIPv6()

$found = $false
foreach($l in Get-AzLocation) {
    foreach($z in Get-AzNetworkServiceTag -Location $l.Location) {
        foreach($v in $z.Values) {
            foreach($p in $v.properties.addressPrefixes) {
                try {
                    if($isipv4 -and $p.Contains(":")) {
                        continue
                    }
                    if($isipv6 -and $p.Contains(".")) {
                        continue
                    }
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
