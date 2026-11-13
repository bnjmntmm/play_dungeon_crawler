@echo off
setlocal EnableExtensions
set "LAN_SETUP_SELF=%~f0"
set "LAN_SETUP_PS=%TEMP%\LAN_Share_Setup_%RANDOM%_%RANDOM%.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:LAN_SETUP_SELF); $m='### POWERSHELL PAYLOAD BELOW ###'; $p=$s.LastIndexOf($m); if($p -lt 0){exit 5}; [IO.File]::WriteAllText($env:LAN_SETUP_PS,$s.Substring($p+$m.Length).TrimStart([char]13,[char]10),[Text.Encoding]::UTF8)"
if errorlevel 1 (
  echo Could not extract the PowerShell helper.
  pause
  exit /b 1
)
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%LAN_SETUP_PS%"
set "LAN_SETUP_RC=%ERRORLEVEL%"
del /q "%LAN_SETUP_PS%" >nul 2>&1
echo.
pause
exit /b %LAN_SETUP_RC%
### POWERSHELL PAYLOAD BELOW ###
$ErrorActionPreference = 'Stop'
$Root      = Join-Path $env:ProgramData 'LANShareSetup'
$StateFile = Join-Path $Root 'rollback.tmp'
$Subnet    = '192.168.10.0/24'
$ShareName = 'custom_data'
$HostIP    = '192.168.10.50'
$RemoteUNC = "\\$HostIP\$ShareName"

# The only three PCs that will ever exist
$Stations = @(
    @{ Key = '1'; Name = 'Art-Station-Setup';      IP = '192.168.10.50'; IsHost = $true  },
    @{ Key = '2'; Name = 'Game-Dev-Station-Setup'; IP = '192.168.10.51'; IsHost = $false },
    @{ Key = '3'; Name = 'Play-Station-Setup';     IP = '192.168.10.52'; IsHost = $false }
)

function Heading([string]$title) {
    Write-Host ''
    Write-Host ('=' * 65) -ForegroundColor Cyan
    Write-Host ('  ' + $title) -ForegroundColor Cyan
    Write-Host ('=' * 65) -ForegroundColor Cyan
}
function Ask-Yes([string]$prompt, [bool]$default = $false) {
    $suffix = if ($default) { '[Y/n]' } else { '[y/N]' }
    $answer = (Read-Host "$prompt $suffix").Trim()
    if (-not $answer) { return $default }
    return ($answer -match '^(y|yes|j|ja)$')
}
function Save-State($state) {
    if (-not (Test-Path -LiteralPath $Root)) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }
    $tmp = $StateFile + '.new'
    $state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $StateFile -Force
}
function Reg-Backup([string]$path, [string]$name) {
    $item = Get-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue
    if ($null -eq $item) { return @{ Exists = $false; Value = $null } }
    return @{ Exists = $true; Value = $item.$name }
}
function Reg-Restore([string]$path, [string]$name, $entry) {
    if ($entry.Exists) {
        New-Item -Path $path -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -LiteralPath $path -Name $name -Value $entry.Value
    } else {
        Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue
    }
}
function Get-GuestUser {
    return Get-LocalUser -ErrorAction SilentlyContinue | Where-Object {
        $_.SID -and $_.SID.Value -match '-501$'
    } | Select-Object -First 1
}
# Folder picker; falls back to typing a path if the dialog is cancelled
function Read-Folder([string]$description) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $picker = New-Object System.Windows.Forms.FolderBrowserDialog
        $picker.Description = $description
        $picker.ShowNewFolderButton = $true
        if ($picker.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $picker.SelectedPath }
    } catch { Write-Warning "Folder picker unavailable: $($_.Exception.Message)" }
    return (Read-Host "$description - type full path (empty = abort)").Trim().Trim('"')
}

# ---------- Adapter backup / restore ----------
function Get-AdapterSnapshot($adapter) {
    $idx = [int]$adapter.ifIndex
    $ipIf = Get-NetIPInterface -InterfaceIndex $idx -AddressFamily IPv4
    $addresses = @(Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -ne '0.0.0.0' } |
        ForEach-Object { @{ IPAddress = $_.IPAddress; PrefixLength = [int]$_.PrefixLength } })
    $routes = @(Get-NetRoute -InterfaceIndex $idx -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        ForEach-Object { @{ NextHop = $_.NextHop; RouteMetric = [int]$_.RouteMetric } })
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{' + $adapter.InterfaceGuid.ToString() + '}'
    $nameServer = (Get-ItemProperty -LiteralPath $regPath -Name NameServer -ErrorAction SilentlyContinue).NameServer
    $profile = Get-NetConnectionProfile -InterfaceIndex $idx -ErrorAction SilentlyContinue
    return @{
        Index           = $idx
        Guid            = $adapter.InterfaceGuid.ToString()
        Name            = $adapter.Name
        Dhcp            = ($ipIf.Dhcp.ToString() -eq 'Enabled')
        Addresses       = $addresses
        Routes          = $routes
        StaticDns       = [string]$nameServer
        NetworkCategory = $(if ($profile) { $profile.NetworkCategory.ToString() } else { '' })
    }
}
function Set-StaticLAN($index, [string]$address) {
    Write-Host "Configuring IPv4: $address /24, no gateway, no DNS ..."
    Set-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -Dhcp Disabled
    Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    Get-NetRoute -InterfaceIndex $index -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 -IPAddress $address -PrefixLength 24 | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $index -ResetServerAddresses
    try { Set-NetConnectionProfile -InterfaceIndex $index -NetworkCategory Private -ErrorAction Stop }
    catch { Write-Warning 'Could not set the network to Private (subnet-scoped firewall rule still applies).' }
}
function Restore-Adapter($cfg) {
    $index = [int]$cfg.Index
    $adapter = Get-NetAdapter -InterfaceIndex $index -ErrorAction SilentlyContinue
    if (-not $adapter -or ($adapter.InterfaceGuid.ToString() -ne [string]$cfg.Guid)) {
        $adapter = Get-NetAdapter | Where-Object { $_.InterfaceGuid.ToString() -eq [string]$cfg.Guid } | Select-Object -First 1
        if (-not $adapter) { throw 'Original Ethernet adapter is missing; cannot restore its IP settings.' }
        $index = [int]$adapter.ifIndex
    }
    Write-Host "Restoring $($cfg.Name) ..."
    Set-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -Dhcp Disabled
    Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    Get-NetRoute -InterfaceIndex $index -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
    if ($cfg.Dhcp) {
        Set-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -Dhcp Enabled
        Set-DnsClientServerAddress -InterfaceIndex $index -ResetServerAddresses
    } else {
        foreach ($ip in @($cfg.Addresses)) {
            if ($ip.IPAddress -and $ip.IPAddress -notlike '169.254.*') {
                New-NetIPAddress -InterfaceIndex $index -IPAddress $ip.IPAddress -PrefixLength ([int]$ip.PrefixLength) | Out-Null
            }
        }
        foreach ($route in @($cfg.Routes)) {
            if ($route.NextHop -and $route.NextHop -ne '0.0.0.0') {
                New-NetRoute -InterfaceIndex $index -DestinationPrefix '0.0.0.0/0' -NextHop $route.NextHop -RouteMetric ([int]$route.RouteMetric) | Out-Null
            }
        }
        $dns = ([string]$cfg.StaticDns).Trim()
        if ($dns) { Set-DnsClientServerAddress -InterfaceIndex $index -ServerAddresses @($dns -split '[,\s]+' | Where-Object { $_ }) }
        else      { Set-DnsClientServerAddress -InterfaceIndex $index -ResetServerAddresses }
    }
    if ($cfg.NetworkCategory) {
        try { Set-NetConnectionProfile -InterfaceIndex $index -NetworkCategory $cfg.NetworkCategory -ErrorAction Stop }
        catch { Write-Warning 'Could not restore the previous network profile category.' }
    }
}

# ---------- Rollback ----------
function Restore-All($state) {
    Heading 'Rollback / revert previous setup'
    if ([string]$state.Machine -ne $env:COMPUTERNAME) {
        Write-Warning 'This backup was made on another PC. Rollback has been stopped.'
        return
    }
    $problems = New-Object System.Collections.Generic.List[string]
    if ($state.Link -and $state.Link.Path) {
        try {
            $item = Get-Item -LiteralPath $state.Link.Path -Force -ErrorAction SilentlyContinue
            if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -and ($item.LinkType -eq 'SymbolicLink')) {
                if (@($item.Target) -contains [string]$state.Link.Target) {
                    [System.IO.Directory]::Delete([string]$state.Link.Path)
                    Write-Host "Removed link: $($state.Link.Path)"
                } else { Write-Warning 'Link points somewhere else now; not removing it.' }
            }
        } catch { $problems.Add("Link: $($_.Exception.Message)") }
    }
    if ($state.Share -and $state.Share.Name) {
        try {
            $share = Get-SmbShare -Name $state.Share.Name -ErrorAction SilentlyContinue
            if ($share -and ($share.Path -ieq [string]$state.Share.Path)) {
                Remove-SmbShare -Name $state.Share.Name -Force -Confirm:$false
                Write-Host "Removed SMB share: $($state.Share.Name)"
            } elseif ($share) { Write-Warning 'Share path was changed; not removing the share.' }
        } catch { $problems.Add("Share: $($_.Exception.Message)") }
    }
    if ($state.Acl -and $state.Acl.Path -and $state.Acl.Sddl) {
        try {
            if (Test-Path -LiteralPath $state.Acl.Path -PathType Container) {
                $acl = Get-Acl -LiteralPath $state.Acl.Path
                $acl.SetSecurityDescriptorSddlForm([string]$state.Acl.Sddl, [System.Security.AccessControl.AccessControlSections]::Access)
                Set-Acl -LiteralPath $state.Acl.Path -AclObject $acl
                Write-Host "Restored folder ACL: $($state.Acl.Path)"
            }
        } catch { $problems.Add("Folder ACL: $($_.Exception.Message)") }
    }
    foreach ($ruleName in @($state.FirewallRules)) {
        if (-not $ruleName) { continue }
        try {
            if (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue) {
                Remove-NetFirewallRule -Name $ruleName -ErrorAction Stop
            }
        } catch { $problems.Add("Firewall: $($_.Exception.Message)") }
    }
    try {
        Set-SmbClientConfiguration -EnableInsecureGuestLogons ([bool]$state.Security.ClientGuest) -Force | Out-Null
        if ($state.Security.SigningChanged) {
            Set-SmbClientConfiguration -RequireSecuritySignature ([bool]$state.Security.ClientSigning) -Force | Out-Null
            Set-SmbServerConfiguration -RequireSecuritySignature ([bool]$state.Security.ServerSigning) -Force | Out-Null
        }
        if ($state.Security.HostGuestChanged) {
            Reg-Restore 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'ForceGuest' $state.Security.ForceGuest
            $guest = Get-GuestUser
            if ($guest -and (-not [bool]$state.Security.GuestEnabled)) { Disable-LocalUser -Name $guest.Name }
        }
    } catch { $problems.Add("Guest settings: $($_.Exception.Message)") }
    try { Restore-Adapter $state.Adapter } catch { $problems.Add("IPv4 restore: $($_.Exception.Message)") }
    if ($problems.Count -eq 0) {
        Remove-Item -LiteralPath $StateFile -Force
        Write-Host 'Rollback complete; backup removed.' -ForegroundColor Green
    } else {
        Write-Warning 'Rollback partly failed. Backup retained for another attempt.'
        foreach ($problem in $problems) { Write-Warning $problem }
        Write-Host "State file: $StateFile"
    }
}

# ---------- Fresh setup ----------
function Setup-New {
    Heading 'Windows LAN setup - 3 PC network'
    foreach ($s in $Stations) { Write-Host ("  [{0}] {1,-24} {2}" -f $s.Key, $s.Name, $s.IP) }
    $pick = (Read-Host 'Pick a setup (1-3)').Trim()
    $station = $Stations | Where-Object { $_.Key -eq $pick } | Select-Object -First 1
    if (-not $station) { throw 'Invalid choice.' }
    $ip = $station.IP

    # ---- Adapter ----
    $adapters = @(Get-NetAdapter | Where-Object { $_.HardwareInterface } | Sort-Object Name)
    if (-not $adapters) { $adapters = @(Get-NetAdapter | Sort-Object Name) }
    if ($adapters.Count -eq 1) {
        $adapter = $adapters[0]
    } else {
        Write-Host 'Available adapters (pick your wired Ethernet adapter):'
        for ($i = 0; $i -lt $adapters.Count; $i++) {
            Write-Host ("  [{0}] {1} | {2} | {3}" -f ($i + 1), $adapters[$i].Name, $adapters[$i].Status, $adapters[$i].InterfaceDescription)
        }
        $n = 0
        if (-not [int]::TryParse((Read-Host 'Adapter number').Trim(), [ref]$n) -or $n -lt 1 -or $n -gt $adapters.Count) {
            throw 'Invalid adapter selection.'
        }
        $adapter = $adapters[$n - 1]
    }

    # ---- Gather every folder choice BEFORE changing anything ----
    $folder = $null; $linkPath = $null
    if ($station.IsHost) {
        $folder = Read-Folder "Choose the custom_data folder to SHARE"
        if (-not $folder -or -not (Test-Path -LiteralPath $folder -PathType Container)) { throw "Folder not found: $folder" }
        $folder = (Get-Item -LiteralPath $folder).FullName.TrimEnd('\')
        if ($folder -ieq [IO.Path]::GetPathRoot($folder).TrimEnd('\')) { throw 'Sharing a whole drive root is blocked. Select a subfolder.' }
        $blocked = @($env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData,
                     (Join-Path $env:SystemDrive 'Users'), $env:USERPROFILE) | Where-Object { $_ }
        foreach ($b in $blocked) { if ($folder -ieq $b.TrimEnd('\')) { throw "This folder cannot be shared by the script: $folder" } }
    } else {
        $parent = Read-Folder "Choose where the '$ShareName' symlink should be created"
        if (-not $parent -or -not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Folder not found: $parent" }
        $linkPath = Join-Path (Get-Item -LiteralPath $parent).FullName $ShareName
        if (Test-Path -LiteralPath $linkPath) { throw "Already exists: $linkPath" }
    }

    Write-Host ''
    Write-Host "Setup:    $($station.Name)"
    Write-Host "Adapter:  $($adapter.Name)  ->  $ip /24 (no gateway, no DNS)"
    if ($station.IsHost) { Write-Host "Share:    $folder  ->  $RemoteUNC (guest, read/write, subnet only)" }
    else                 { Write-Host "Link:     $linkPath  ->  $RemoteUNC" }
    Write-Warning 'This enables password-free Guest SMB. Use ONLY on an isolated, trusted Ethernet network.'
    Write-Warning 'Changing the adapter IP may disconnect remote sessions / Internet.'
    if (-not (Ask-Yes 'Apply?')) { return }

    if (Get-NetIPAddress -AddressFamily IPv4 -IPAddress $ip -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceIndex -ne $adapter.ifIndex }) {
        throw "Address $ip is already configured on a different local adapter."
    }
    if ($station.IsHost -and (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) {
        throw "Share already exists: $ShareName"
    }

    # ---- Back up, then apply ----
    $client = Get-SmbClientConfiguration
    $server = Get-SmbServerConfiguration
    $guest  = Get-GuestUser
    $state = @{
        Version = 2; Machine = $env:COMPUTERNAME; Date = (Get-Date).ToString('o')
        Station = $station.Name; SelectedIP = $ip
        Adapter = (Get-AdapterSnapshot $adapter)
        Security = @{
            ClientGuest = [bool]$client.EnableInsecureGuestLogons
            ClientSigning = [bool]$client.RequireSecuritySignature
            ServerSigning = [bool]$server.RequireSecuritySignature
            SigningChanged = $false
            ForceGuest = (Reg-Backup 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'ForceGuest')
            GuestEnabled = $(if ($guest) { [bool]$guest.Enabled } else { $false })
            HostGuestChanged = $false
        }
        FirewallRules = @(); Acl = $null; Share = $null; Link = $null
    }
    Save-State $state   # saved first, so rollback works even after an error
    try {
        Set-StaticLAN -index $adapter.ifIndex -address $ip
        Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -Force | Out-Null

        if ($client.RequireSecuritySignature -or $server.RequireSecuritySignature) {
            Write-Warning 'SMB signing is required on this PC; guest connections will fail while it is on.'
            if (Ask-Yes 'Disable required SMB signing on this PC? (SECURITY RISK)') {
                $state.Security.SigningChanged = $true
                Save-State $state
                Set-SmbClientConfiguration -RequireSecuritySignature $false -Force | Out-Null
                Set-SmbServerConfiguration -RequireSecuritySignature $false -Force | Out-Null
            }
        }

        if ($station.IsHost) {
            # Firewall: inbound SMB from the LAN subnet only
            $ruleName = 'LANShareSetup-SMB-' + [guid]::NewGuid().ToString('N')
            $state.FirewallRules = @($ruleName); Save-State $state
            New-NetFirewallRule -Name $ruleName -DisplayName 'LAN Share Setup (SMB 445, subnet only)' `
                -Direction Inbound -Action Allow -Enabled True -Profile Any -Protocol TCP `
                -LocalPort 445 -RemoteAddress $Subnet | Out-Null

            # Guest-only access + share
            $everyone = ([Security.Principal.SecurityIdentifier]'S-1-1-0').Translate([Security.Principal.NTAccount]).Value
            $state.Acl   = @{ Path = $folder; Sddl = (Get-Acl -LiteralPath $folder).Sddl }
            $state.Share = @{ Name = $ShareName; Path = $folder }
            $state.Security.HostGuestChanged = $true
            Save-State $state
            Set-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name ForceGuest -Value 1
            $g = Get-GuestUser
            if ($g -and -not $g.Enabled) { Enable-LocalUser -Name $g.Name }
            if (-not $g) { Write-Warning 'Built-in Guest account not found; passwordless SMB may not work.' }
            & icacls.exe $folder '/grant' '*S-1-1-0:(OI)(CI)M' | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "icacls failed with exit code $LASTEXITCODE" }
            New-SmbShare -Name $ShareName -Path $folder -ChangeAccess $everyone | Out-Null
            Write-Host "Shared as $RemoteUNC" -ForegroundColor Green
        } else {
            # mklink /D forces a DIRECTORY link even while the host is offline
            $state.Link = @{ Path = $linkPath; Target = $RemoteUNC }
            Save-State $state
            & cmd.exe /c mklink /D "`"$linkPath`"" "`"$RemoteUNC`"" | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "mklink failed with exit code $LASTEXITCODE" }
            Write-Host "Created link: $linkPath -> $RemoteUNC" -ForegroundColor Green
            Write-Host 'The Art Station must be online. Files stay on that PC; this is not an offline sync.'
        }

        Heading 'Done'
        Write-Host "Setup:   $($station.Name)"
        Write-Host "IPv4:    $ip /24, no gateway, no DNS"
        Write-Host "Rollback saved: $StateFile"
        Write-Host 'Run this BAT again on this PC to undo everything it changed.'
        Write-Warning 'If Windows 11 still blocks guest access, authenticated SMB is required.'
    } catch {
        Write-Warning "Setup stopped: $($_.Exception.Message)"
        Write-Host 'Run this BAT again to revert what was applied.'
        throw
    }
}

# ---------- Main ----------
try {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'Requesting Administrator privileges (UAC) ...'
        $argList = '-NoProfile -STA -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -Wait
        exit 0
    }
    if (Test-Path -LiteralPath $StateFile) {
        Heading 'Existing setup detected'
        $state = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
        Write-Host "Setup: $($state.Station)   IP: $($state.SelectedIP)"
        if ($state.Share) { Write-Host "Share: $($state.Share.Name) -> $($state.Share.Path)" }
        if ($state.Link)  { Write-Host "Link:  $($state.Link.Path) -> $($state.Link.Target)" }
        if (Ask-Yes 'Revert previous setup now?') { Restore-All $state }
        else { Write-Host 'No changes made. Revert before starting a new configuration.' }
    } else { Setup-New }
} catch {
    Write-Host ''
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'If rollback.tmp exists, run this BAT again and choose revert.'
    exit 1
}
