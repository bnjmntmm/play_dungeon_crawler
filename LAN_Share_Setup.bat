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
$Root = Join-Path $env:ProgramData 'LANShareSetup'
$StateFile = Join-Path $Root 'rollback.tmp'
$Subnet = '192.168.10.0/24'

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
    if (-not (Test-Path -LiteralPath $Root)) {
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
    }
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
function Pick-Folder([string]$description) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $picker = New-Object System.Windows.Forms.FolderBrowserDialog
        $picker.Description = $description
        $picker.ShowNewFolderButton = $true
        if ($picker.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $picker.SelectedPath
        }
    } catch {
        Write-Warning "Folder picker unavailable: $($_.Exception.Message)"
    }
    return ''
}
function Read-Folder([string]$purpose) {
    Write-Host "Select a $purpose folder: [P]icker, [T]ype a path, or [S]kip"
    $method = (Read-Host 'Option [P]').Trim()
    if ($method -match '^(s|skip)$') { return '' }
    if ($method -match '^(t|type)$') { return (Read-Host 'Full folder path').Trim().Trim('"') }
    return Pick-Folder "Choose the $purpose folder (Cancel = skip)"
}
function Get-AdapterSnapshot($adapter) {
    $idx = [int]$adapter.ifIndex
    $ipIf = Get-NetIPInterface -InterfaceIndex $idx -AddressFamily IPv4
    $addresses = @(Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -ne '0.0.0.0' } |
        ForEach-Object { @{ IPAddress = $_.IPAddress; PrefixLength = [int]$_.PrefixLength } })
    $routes = @(Get-NetRoute -InterfaceIndex $idx -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        ForEach-Object { @{ NextHop = $_.NextHop; RouteMetric = [int]$_.RouteMetric } })
    $dns = @( (Get-DnsClientServerAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses )
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
        Dns             = $dns
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
    catch { Write-Warning 'Could not change this network to Private. Subnet-scoped SMB firewall access will still be added.' }
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
        if ($dns) {
            $dnsServers = @($dns -split '[,\s]+' | Where-Object { $_ })
            Set-DnsClientServerAddress -InterfaceIndex $index -ServerAddresses $dnsServers
        } else {
            Set-DnsClientServerAddress -InterfaceIndex $index -ResetServerAddresses
        }
    }
    if ($cfg.NetworkCategory) {
        try { Set-NetConnectionProfile -InterfaceIndex $index -NetworkCategory $cfg.NetworkCategory -ErrorAction Stop }
        catch { Write-Warning 'Could not restore the previous network profile category.' }
    }
}
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
            if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
                ($item.LinkType -eq 'SymbolicLink')) {
                $targets = @($item.Target)
                if ($targets -contains [string]$state.Link.Target) {
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
        }
        catch { $problems.Add("Firewall: $($_.Exception.Message)") }
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
            if ($guest -and (-not [bool]$state.Security.GuestEnabled)) {
                Disable-LocalUser -Name $guest.Name
            }
        }
    } catch { $problems.Add("Guest settings: $($_.Exception.Message)") }
    try { Restore-Adapter $state.Adapter }
    catch { $problems.Add("IPv4 restore: $($_.Exception.Message)") }
    if ($problems.Count -eq 0) {
        Remove-Item -LiteralPath $StateFile -Force
        Write-Host 'Rollback complete; backup removed.' -ForegroundColor Green
    } else {
        Write-Warning 'Rollback partly failed. Backup retained for another attempt.'
        foreach ($problem in $problems) { Write-Warning $problem }
        Write-Host "State file: $StateFile"
    }
}
function Setup-Sharing($state) {
    Heading 'Sharing or directory symlink'
    Write-Host 'Folder sharing uses SMB. A directory symlink points at remote files; it does NOT sync offline copies.'
    $folder = Read-Folder 'local folder to SHARE'
    if ($folder) {
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
            throw "Folder does not exist: $folder"
        }
        $folder = (Get-Item -LiteralPath $folder).FullName.TrimEnd('\')
        $rootPath = [IO.Path]::GetPathRoot($folder).TrimEnd('\')
        if ($folder -ieq $rootPath) { throw 'Sharing an entire drive root is blocked. Select a subfolder.' }
        $prohibited = @($env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData,
            (Join-Path $env:SystemDrive 'Users'), $env:USERPROFILE) | Where-Object { $_ }
        foreach ($p in $prohibited) {
            if ($folder -ieq $p.TrimEnd('\')) { throw "System or user-profile root cannot be shared by this script: $folder" }
        }
        $suggested = (Split-Path -Path $folder -Leaf) -replace '[^A-Za-z0-9_-]', '_'
        if (-not $suggested) { $suggested = 'CustomData' }
        $shareName = (Read-Host "SMB share name [$suggested]").Trim()
        if (-not $shareName) { $shareName = $suggested }
        if ($shareName -notmatch '^[A-Za-z0-9_-]{1,70}$') { throw 'Share name must be 1-70 letters, digits, _ or -.' }
        if (Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue) { throw "Share already exists: $shareName" }
        $mode = (Read-Host 'Access: [R]ead only or [M]odify files [M]').Trim()
        $permission = if ($mode -match '^(r|read)$') { 'RX' } else { 'M' }
        $everyone = ([System.Security.Principal.SecurityIdentifier]'S-1-1-0').Translate([System.Security.Principal.NTAccount]).Value
        $state.Acl = @{ Path = $folder; Sddl = (Get-Acl -LiteralPath $folder).Sddl }
        $state.Share = @{ Name = $shareName; Path = $folder }
        $state.Security.HostGuestChanged = $true
        Save-State $state
        Write-Host 'Configuring Guest-only local network access on this host ...'
        Set-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name ForceGuest -Value 1
        $guest = Get-GuestUser
        if ($guest -and -not $guest.Enabled) { Enable-LocalUser -Name $guest.Name }
        if (-not $guest) { Write-Warning 'Built-in Guest account not found. Passwordless SMB hosting may not work.' }
        & icacls.exe $folder '/grant' ("*S-1-1-0:(OI)(CI)" + $permission) | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Failed to grant NTFS permissions. icacls exit code: $LASTEXITCODE" }
        if ($permission -eq 'M') {
            New-SmbShare -Name $shareName -Path $folder -ChangeAccess $everyone | Out-Null
        } else {
            New-SmbShare -Name $shareName -Path $folder -ReadAccess $everyone | Out-Null
        }
        Write-Host "Shared! From another PC enter: \\$($state.SelectedIP)\$shareName" -ForegroundColor Green
    } else {
        if (Ask-Yes 'No folder selected. Create a LOCAL symlink pointing to another PC SMB share?') {
            $remote = (Read-Host 'Remote UNC path (example: \\192.168.10.50\CustomData)').Trim().Trim('"').TrimEnd('\')
            if ($remote -notmatch '^\\\\([^\\]+)\\([^\\]+)(?:\\.*)?$') {
                throw 'Remote path must be a UNC share such as \\192.168.10.50\CustomData.'
            }
            $parent = Read-Folder 'PARENT directory for the new symlink'
            if (-not $parent) { Write-Host 'Skipped symlink.'; return }
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Parent folder does not exist: $parent" }
            $linkName = (Read-Host 'NEW link folder name (e.g. SharedData)').Trim()
            if ($linkName -notmatch '^[^\\/:*?"<>|.][^\\/:*?"<>|]*$' -or $linkName.EndsWith('.')) {
                throw 'Invalid link name. Do not use slashes or Windows-forbidden characters.'
            }
            $linkPath = Join-Path (Get-Item -LiteralPath $parent).FullName $linkName
            if (Test-Path -LiteralPath $linkPath) { throw "Destination already exists: $linkPath" }
            $state.Link = @{ Path = $linkPath; Target = $remote }
            Save-State $state
            New-Item -ItemType SymbolicLink -Path $linkPath -Target $remote | Out-Null
            Write-Host "Created directory symlink: $linkPath -> $remote" -ForegroundColor Green
            Write-Host 'The remote machine must be online. Changes happen on the remote files; this is not offline sync.'
        }
    }
}
function Setup-New {
    Heading 'Windows LAN + SMB share setup'
    Write-Host 'Target LAN: 192.168.10.50 - 192.168.10.57, mask 255.255.255.0'
    Write-Host 'Gateway: NONE    IPv4 DNS: NONE'
    Write-Host 'Public/Private SMB firewall: only incoming connections from 192.168.10.0/24'
    Write-Warning 'This enables password-free Guest SMB. Use ONLY on an isolated, trusted Ethernet network.'
    Write-Warning 'Changing an adapter IP may temporarily disconnect remote sessions / Internet.'
    if (-not (Ask-Yes 'Apply these LAN sharing settings?')) { return }
    Write-Host ''
    for ($n = 50; $n -le 57; $n++) { Write-Host ("  [{0}]  192.168.10.{0}" -f $n) }
    $lastOctet = (Read-Host 'Choose address number (50-57)').Trim()
    if ($lastOctet -notmatch '^5[0-7]$') { throw 'Invalid IP choice.' }
    $selectedIP = "192.168.10.$lastOctet"
    $adapters = @(Get-NetAdapter | Where-Object { $_.HardwareInterface -or $_.InterfaceDescription -match 'Ethernet' } |
        Sort-Object -Property Name)
    if (-not $adapters) { $adapters = @(Get-NetAdapter | Sort-Object -Property Name) }
    Write-Host ''
    Write-Host 'Available adapters (select your REAL wired Ethernet adapter):'
    for ($i = 0; $i -lt $adapters.Count; $i++) {
        Write-Host ("  [{0}] {1} | {2} | {3}" -f ($i + 1), $adapters[$i].Name,
            $adapters[$i].Status, $adapters[$i].InterfaceDescription)
    }
    $choice = (Read-Host 'Adapter number').Trim()
    $number = 0
    if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt $adapters.Count) {
        throw 'Invalid adapter selection.'
    }
    $adapter = $adapters[$number - 1]
    if (-not (Ask-Yes "Set $($adapter.Name) to $selectedIP/24?")) { return }
    $conflicts = @(Get-NetIPAddress -AddressFamily IPv4 -IPAddress $selectedIP -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceIndex -ne $adapter.ifIndex })
    if ($conflicts.Count) { throw "Address $selectedIP is already configured on a different local adapter." }
    $client = Get-SmbClientConfiguration
    $server = Get-SmbServerConfiguration
    $guest = Get-GuestUser
    $state = @{
        Version = 1
        Machine = $env:COMPUTERNAME
        Date = (Get-Date).ToString('o')
        SelectedIP = $selectedIP
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
        FirewallRules = @()
        Acl = $null
        Share = $null
        Link = $null
    }
    Save-State $state  # Save before any changes so rollback is available after an error.
    try {
        Set-StaticLAN -index $adapter.ifIndex -address $selectedIP
        Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -Force | Out-Null
        $ruleName = 'LANShareSetup-SMB-' + [guid]::NewGuid().ToString('N')
        $state.FirewallRules = @($ruleName)
        Save-State $state
        New-NetFirewallRule -Name $ruleName -DisplayName 'LAN Share Setup (SMB 445, subnet only)' `
            -Direction Inbound -Action Allow -Enabled True -Profile Any -Protocol TCP `
            -LocalPort 445 -RemoteAddress $Subnet | Out-Null
        Write-Host 'Firewall: inbound TCP 445 enabled for 192.168.10.0/24 (Public and Private).'
        if ($client.RequireSecuritySignature -or $server.RequireSecuritySignature) {
            Write-Warning 'SMB signing is required on this PC. Guest connections on newer Windows 11 may fail.'
            Write-Warning 'Disabling signing reduces protection against impersonation and tampering.'
            if (Ask-Yes 'Disable required SMB signing on this PC for passwordless SMB? (SECURITY RISK)') {
                $state.Security.SigningChanged = $true
                Save-State $state
                Set-SmbClientConfiguration -RequireSecuritySignature $false -Force | Out-Null
                Set-SmbServerConfiguration -RequireSecuritySignature $false -Force | Out-Null
            }
        }
        Setup-Sharing $state
        Heading 'Summary'
        Write-Host "Local IPv4: $selectedIP /24"
        Write-Host "Adapter:    $($adapter.Name)"
        Write-Host 'Gateway:    None'
        Write-Host 'IPv4 DNS:   None (reset)'
        Write-Host "Saved rollback: $StateFile"
        Write-Host 'Run this same BAT file again to restore settings and remove the link/share it created.'
        Write-Host 'Other PCs must have UNIQUE addresses in the same 192.168.10.0/24 subnet.'
        Write-Host 'Browse SMB shares by UNC IP path, e.g. \\192.168.10.50\CustomData.'
        Write-Warning 'Some Windows 11 security policies still block guest connections. Use authenticated SMB if they do.'
    } catch {
        Write-Warning "Setup stopped: $($_.Exception.Message)"
        Write-Host "Rollback file retained: $StateFile"
        Write-Host 'Run this BAT again to restore previous network/settings.'
        throw
    }
}

try {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'Requesting Administrator privileges (UAC) ...'
        $args = '-NoProfile -STA -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
        Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -Wait
        exit 0
    }
    if (Test-Path -LiteralPath $StateFile) {
        Heading 'Existing setup detected'
        Write-Host "Rollback state: $StateFile"
        $state = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
        Write-Host "Saved IP: $($state.SelectedIP)"
        if ($state.Share) { Write-Host "Saved share: $($state.Share.Name) -> $($state.Share.Path)" }
        if ($state.Link) { Write-Host "Saved link: $($state.Link.Path) -> $($state.Link.Target)" }
        if (Ask-Yes 'Revert previous setup now?') { Restore-All $state }
        else { Write-Host 'No changes made. Revert before starting a new configuration.' }
    } else { Setup-New }
} catch {
    Write-Host ''
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host "If rollback.tmp exists, run this BAT again and choose revert."
    exit 1
}
