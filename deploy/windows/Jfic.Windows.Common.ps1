$script:JficTargetJellyfin = '10.11.11'
$script:JficPluginAbi = '1.0.0.0'
$script:JficStateRoot = Join-Path $env:ProgramData 'jellyfin-image-controls'
$script:JficStateFile = Join-Path $script:JficStateRoot 'install-state.json'
$script:JficSafeModeMarker = Join-Path $script:JficStateRoot 'disable-ffmpeg-patch'
$script:JficWebEnvironmentName = 'JELLYFIN_WEB_DIR'

function Write-JficStep {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[JFIC] $Message"
}

function Write-JficWarn {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Warning "[JFIC] $Message"
}

function Test-JficAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-JficAdministrator {
    if (-not (Test-JficAdministrator)) {
        throw 'Run PowerShell as Administrator and launch the command again.'
    }
}

function Expand-JficRegistryPathValue {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    return [Environment]::ExpandEnvironmentVariables($Value)
}

function Get-JficRegistryInstall {
    $keys = @(
        'HKLM:\SOFTWARE\WOW6432Node\Jellyfin\Server',
        'HKLM:\SOFTWARE\Jellyfin\Server'
    )

    foreach ($key in $keys) {
        if (-not (Test-Path $key)) { continue }
        $value = Get-ItemProperty -Path $key
        $installFolder = Expand-JficRegistryPathValue $value.InstallFolder
        $dataFolder = Expand-JficRegistryPathValue $value.DataFolder
        if (-not [string]::IsNullOrWhiteSpace($installFolder)) {
            return [pscustomobject]@{
                RegistryPath = $key
                InstallFolder = $installFolder
                DataFolder = $dataFolder
            }
        }
    }

    return $null
}

function Get-JficService {
    $service = Get-Service -Name 'JellyfinServer' -ErrorAction SilentlyContinue
    if ($null -ne $service) { return $service }

    $candidate = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '(?i)jellyfin' -or
            $_.DisplayName -match '(?i)jellyfin' -or
            $_.PathName -match '(?i)jellyfin(?:\.exe|\.dll)'
        } |
        Select-Object -First 1

    if ($null -ne $candidate) {
        return Get-Service -Name $candidate.Name -ErrorAction SilentlyContinue
    }

    return $null
}

function Get-JficServiceRegistryPath {
    param([Parameter(Mandatory = $true)][string]$ServiceName)
    return "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
}

function Get-JficServiceImagePath {
    param([Parameter(Mandatory = $true)][string]$ServiceName)
    $path = Get-JficServiceRegistryPath $ServiceName
    if (-not (Test-Path $path)) { return $null }
    return (Get-ItemProperty -Path $path -Name ImagePath -ErrorAction SilentlyContinue).ImagePath
}

function Get-JficServiceEnvironment {
    param([Parameter(Mandatory = $true)][string]$ServiceName)
    $path = Get-JficServiceRegistryPath $ServiceName
    try {
        $value = Get-ItemProperty -Path $path -Name Environment -ErrorAction Stop
        return @($value.Environment | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    catch {
        return @()
    }
}

function Set-JficServiceEnvironment {
    param(
        [Parameter(Mandatory = $true)][string]$ServiceName,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Values
    )

    $path = Get-JficServiceRegistryPath $ServiceName
    if ($Values.Count -eq 0) {
        Remove-ItemProperty -Path $path -Name Environment -ErrorAction SilentlyContinue
        return
    }

    New-ItemProperty `
        -Path $path `
        -Name Environment `
        -PropertyType MultiString `
        -Value ([string[]]$Values) `
        -Force | Out-Null
}

function Get-JficMachineWebEnvironment {
    $path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    try {
        $item = Get-ItemProperty -Path $path -Name $script:JficWebEnvironmentName -ErrorAction Stop
        $property = $item.PSObject.Properties[$script:JficWebEnvironmentName]
        return [pscustomobject]@{
            Exists = $true
            Value = [string]$property.Value
        }
    }
    catch {
        return [pscustomobject]@{
            Exists = $false
            Value = $null
        }
    }
}

function Set-JficMachineWebEnvironmentRaw {
    param(
        [Parameter(Mandatory = $true)][bool]$Exists,
        [AllowNull()][string]$Value
    )

    if ($Exists) {
        [Environment]::SetEnvironmentVariable(
            $script:JficWebEnvironmentName,
            $Value,
            [EnvironmentVariableTarget]::Machine)
        $env:JELLYFIN_WEB_DIR = $Value
    }
    else {
        [Environment]::SetEnvironmentVariable(
            $script:JficWebEnvironmentName,
            $null,
            [EnvironmentVariableTarget]::Machine)
        Remove-Item Env:JELLYFIN_WEB_DIR -ErrorAction SilentlyContinue
    }
}

function Set-JficWebMachineEnvironment {
    param(
        [Parameter(Mandatory = $true)][string]$WebDirectory,
        [switch]$ForceWebOverride,
        [AllowNull()]$PreviousState
    )

    $current = Get-JficMachineWebEnvironment
    $previousExists = $false
    $previousValue = $null

    $isManagedUpgrade = $false
    if ($null -ne $PreviousState) {
        $mode = [string]$PreviousState.WebEnvironmentMode
        if ($mode -eq 'Machine' -and
            [string]$PreviousState.ManagedWebDir -eq $WebDirectory -and
            $current.Exists -and
            $current.Value -eq $WebDirectory) {
            $isManagedUpgrade = $true
            $previousExists = [bool]$PreviousState.PreviousMachineWebDirExists
            $previousValue = [string]$PreviousState.PreviousMachineWebDirValue
        }
    }

    if (-not $isManagedUpgrade -and $current.Exists -and $current.Value -ne $WebDirectory) {
        if (-not $ForceWebOverride) {
            throw "A machine-level $script:JficWebEnvironmentName already exists: $($current.Value). Use -ForceWebOverride to replace it temporarily, or -NoWeb to install the plugin only."
        }
        $previousExists = $true
        $previousValue = $current.Value
    }

    Set-JficMachineWebEnvironmentRaw -Exists $true -Value $WebDirectory

    return [pscustomobject]@{
        PreviousExists = $previousExists
        PreviousValue = $previousValue
    }
}

function Restore-JficWebMachineEnvironment {
    param(
        [Parameter(Mandatory = $true)][string]$ManagedWebDirectory,
        [bool]$PreviousExists = $false,
        [AllowNull()][string]$PreviousValue
    )

    $current = Get-JficMachineWebEnvironment
    if (-not $current.Exists -or $current.Value -ne $ManagedWebDirectory) {
        # The administrator changed this after JFIC was installed. Do not overwrite it.
        return $false
    }

    Set-JficMachineWebEnvironmentRaw -Exists $PreviousExists -Value $PreviousValue
    return $true
}

function Get-JficJellyfinVersion {
    param([Parameter(Mandatory = $true)][string]$Executable)

    $text = $null
    try {
        $text = (& $Executable --version 2>&1 | Out-String)
    }
    catch {
        $text = $null
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($Executable)
        $text = "$($info.ProductVersion) $($info.FileVersion)"
    }

    $match = [regex]::Match($text, '(?<!\d)(\d+\.\d+\.\d+)(?:\.\d+)?')
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

function Get-JficTrayExecutable {
    param([Parameter(Mandatory = $true)][string]$InstallFolder)

    $candidates = @(
        (Join-Path $InstallFolder 'Jellyfin.Windows.Tray.exe'),
        (Join-Path $InstallFolder 'JellyfinTray.exe')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }

    try {
        $runKey = Get-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'JellyfinTray' -ErrorAction Stop
        $runValue = [string]$runKey.JellyfinTray
        $runMatch = [regex]::Match($runValue, '^\s*(?:"([^"]+\.exe)"|(.+?\.exe))(?:\s|$)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($runMatch.Success) {
            $runExecutable = if (-not [string]::IsNullOrWhiteSpace($runMatch.Groups[1].Value)) { $runMatch.Groups[1].Value } else { $runMatch.Groups[2].Value }
            if (Test-Path $runExecutable) { return $runExecutable }
        }
    }
    catch {
        # Autostart is optional.
    }

    $match = Get-ChildItem -LiteralPath $InstallFolder -File -Filter '*Tray*.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)jellyfin.*tray|tray.*jellyfin' } |
        Select-Object -First 1
    if ($null -ne $match) { return $match.FullName }
    return $null
}

function Get-JficJellyfinServerProcesses {
    param([Parameter(Mandatory = $true)][string]$Executable)

    $target = [IO.Path]::GetFullPath($Executable)
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='jellyfin.exe'" -ErrorAction SilentlyContinue)
    return @($processes | Where-Object {
        if ([string]::IsNullOrWhiteSpace($_.ExecutablePath)) {
            $true
        }
        else {
            try { [IO.Path]::GetFullPath($_.ExecutablePath) -ieq $target } catch { $false }
        }
    })
}

function Get-JficTrayProcesses {
    param([AllowNull()][string]$TrayExecutable)

    $candidates = @()
    $candidates += @(Get-Process -Name 'Jellyfin.Windows.Tray' -ErrorAction SilentlyContinue)
    $candidates += @(Get-Process -Name 'JellyfinTray' -ErrorAction SilentlyContinue)

    if ([string]::IsNullOrWhiteSpace($TrayExecutable)) { return @($candidates) }

    $target = [IO.Path]::GetFullPath($TrayExecutable)
    return @($candidates | Where-Object {
        try {
            if ([string]::IsNullOrWhiteSpace($_.Path)) {
                $true
            }
            else {
                [IO.Path]::GetFullPath($_.Path) -ieq $target
            }
        }
        catch { $true }
    })
}

function Get-JficJellyfinInfo {
    $registry = Get-JficRegistryInstall

    if ($null -ne $registry) {
        $installFolder = $registry.InstallFolder
        $dataFolder = $registry.DataFolder
    }
    else {
        $installFolder = Join-Path $env:ProgramFiles 'Jellyfin\Server'
        $dataFolder = Join-Path $env:ProgramData 'Jellyfin\Server'
    }

    if ([string]::IsNullOrWhiteSpace($dataFolder)) {
        $dataFolder = Join-Path $env:ProgramData 'Jellyfin\Server'
    }

    $executable = Join-Path $installFolder 'jellyfin.exe'
    if (-not (Test-Path $executable)) {
        throw "Jellyfin was not found. Expected jellyfin.exe at: $executable"
    }

    $service = Get-JficService
    $version = Get-JficJellyfinVersion $executable
    $trayExecutable = Get-JficTrayExecutable $installFolder
    $runMode = if ($null -ne $service) { 'Service' } elseif (-not [string]::IsNullOrWhiteSpace($trayExecutable)) { 'Tray' } else { 'Executable' }

    return [pscustomobject]@{
        InstallFolder = $installFolder
        DataFolder = $dataFolder
        Executable = $executable
        NativeWeb = Join-Path $installFolder 'jellyfin-web'
        Version = $version
        Service = $service
        Registry = $registry
        TrayExecutable = $trayExecutable
        RunMode = $runMode
    }
}

function Get-JficPluginDirectory {
    param([Parameter(Mandatory = $true)][string]$DataFolder)
    return Join-Path $DataFolder "plugins\Image Controls_$script:JficPluginAbi"
}

function Get-JficWebOverlayDirectory {
    return Join-Path $script:JficStateRoot 'current\web'
}

function Get-JficFfmpeg {
    param([Parameter(Mandatory = $true)][string]$InstallFolder)

    $candidates = @(
        (Join-Path $InstallFolder 'ffmpeg.exe'),
        (Join-Path $InstallFolder 'ffmpeg\ffmpeg.exe'),
        (Join-Path $InstallFolder 'jellyfin-ffmpeg\ffmpeg.exe')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }

    $command = Get-Command 'ffmpeg.exe' -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    return $null
}

function Get-JficInstallState {
    if (-not (Test-Path $script:JficStateFile)) { return $null }
    try {
        return Get-Content $script:JficStateFile -Raw | ConvertFrom-Json
    }
    catch {
        Write-JficWarn "Could not parse $script:JficStateFile: $($_.Exception.Message)"
        return $null
    }
}

function Save-JficInstallState {
    param([Parameter(Mandatory = $true)]$State)
    New-Item -ItemType Directory -Path $script:JficStateRoot -Force | Out-Null
    $json = $State | ConvertTo-Json -Depth 8
    Set-Content -Path $script:JficStateFile -Value $json -Encoding UTF8
}

function Stop-JficServiceIfRunning {
    param([AllowNull()]$Service)
    if ($null -eq $Service) { return $false }
    $Service.Refresh()
    if ($Service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
        Write-JficStep "Stopping Windows service '$($Service.Name)'..."
        Stop-Service -Name $Service.Name -Force -ErrorAction Stop
        (Get-Service -Name $Service.Name).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
        return $true
    }
    return $false
}

function Start-JficServiceAndVerify {
    param([Parameter(Mandatory = $true)][string]$ServiceName)
    Write-JficStep "Starting Windows service '$ServiceName'..."
    Start-Service -Name $ServiceName -ErrorAction Stop
    $service = Get-Service -Name $ServiceName
    $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
    $service.Refresh()
    if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
        throw "Jellyfin service '$ServiceName' did not reach Running state."
    }
}

function Stop-JficExecutableRuntime {
    param([Parameter(Mandatory = $true)]$Jellyfin)

    $trayProcesses = @(Get-JficTrayProcesses $Jellyfin.TrayExecutable)
    $serverProcesses = @(Get-JficJellyfinServerProcesses $Jellyfin.Executable)

    $state = [pscustomobject]@{
        TrayWasRunning = $trayProcesses.Count -gt 0
        ServerWasRunning = $serverProcesses.Count -gt 0
        TrayExecutable = $Jellyfin.TrayExecutable
    }

    if ($trayProcesses.Count -gt 0) {
        Write-JficStep 'Stopping Jellyfin tray application...'
        foreach ($process in $trayProcesses) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 500
    }

    $serverProcesses = @(Get-JficJellyfinServerProcesses $Jellyfin.Executable)
    if ($serverProcesses.Count -gt 0) {
        Write-JficStep 'Stopping Jellyfin process...'
        foreach ($process in $serverProcesses) {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
        }

        $deadline = (Get-Date).AddSeconds(15)
        do {
            Start-Sleep -Milliseconds 250
            $remaining = @(Get-JficJellyfinServerProcesses $Jellyfin.Executable)
        } while ($remaining.Count -gt 0 -and (Get-Date) -lt $deadline)

        if ($remaining.Count -gt 0) {
            throw 'Jellyfin did not stop within 15 seconds.'
        }
    }

    return $state
}

function Start-JficExecutableRuntime {
    param(
        [Parameter(Mandatory = $true)]$Jellyfin,
        [Parameter(Mandatory = $true)]$RuntimeState
    )

    if (-not $RuntimeState.ServerWasRunning) {
        if ($RuntimeState.TrayWasRunning) {
            Write-JficWarn 'The Jellyfin tray was open while the server was stopped. JFIC left both stopped to preserve the server state; reopen the tray when desired.'
        }
        return
    }

    # A PowerShell window opened before an environment change can carry a stale
    # process environment. Synchronize the value from the machine registry before
    # starting Jellyfin or its tray child process.
    $machineWeb = Get-JficMachineWebEnvironment
    if ($machineWeb.Exists) {
        $env:JELLYFIN_WEB_DIR = $machineWeb.Value
    }
    else {
        Remove-Item Env:JELLYFIN_WEB_DIR -ErrorAction SilentlyContinue
    }

    if ($RuntimeState.TrayWasRunning -and -not [string]::IsNullOrWhiteSpace($RuntimeState.TrayExecutable) -and (Test-Path $RuntimeState.TrayExecutable)) {
        Write-JficStep 'Restarting Jellyfin through the tray application...'
        Start-Process -FilePath $RuntimeState.TrayExecutable | Out-Null
    }
    else {
        Write-JficStep 'Restarting Jellyfin executable...'
        $arguments = "--datadir `"$($Jellyfin.DataFolder)`""
        Start-Process -FilePath $Jellyfin.Executable -ArgumentList $arguments -WindowStyle Hidden | Out-Null
    }

    $deadline = (Get-Date).AddSeconds(20)
    do {
        Start-Sleep -Milliseconds 500
        $running = @(Get-JficJellyfinServerProcesses $Jellyfin.Executable)
    } while ($running.Count -eq 0 -and (Get-Date) -lt $deadline)

    if ($running.Count -eq 0) {
        throw 'Jellyfin did not start within 20 seconds.'
    }
}

function Set-JficWebServiceEnvironment {
    param(
        [Parameter(Mandatory = $true)][string]$ServiceName,
        [Parameter(Mandatory = $true)][string]$WebDirectory,
        [switch]$ForceWebOverride,
        [AllowNull()]$PreviousState
    )

    $current = @(Get-JficServiceEnvironment $ServiceName)
    $currentWeb = @($current | Where-Object { $_ -match '^(?i)JELLYFIN_WEB_DIR=' })
    $managed = "JELLYFIN_WEB_DIR=$WebDirectory"

    $previousWeb = @()
    if ($null -ne $PreviousState -and
        [string]$PreviousState.WebEnvironmentMode -eq 'Service' -and
        $PreviousState.ManagedWebDir -eq $WebDirectory -and
        $currentWeb -contains $managed) {
        $previousWeb = @($PreviousState.PreviousWebDirEntries)
    }
    elseif ($currentWeb.Count -gt 0 -and -not ($currentWeb -contains $managed)) {
        if (-not $ForceWebOverride) {
            throw "A custom JELLYFIN_WEB_DIR already exists for service '$ServiceName': $($currentWeb -join ', '). Use -ForceWebOverride to replace it temporarily, or -NoWeb to install the plugin only."
        }
        $previousWeb = @($currentWeb)
    }

    $updated = @($current | Where-Object { $_ -notmatch '^(?i)JELLYFIN_WEB_DIR=' })
    $updated += $managed
    Set-JficServiceEnvironment -ServiceName $ServiceName -Values $updated
    return @($previousWeb)
}

function Restore-JficWebServiceEnvironment {
    param(
        [Parameter(Mandatory = $true)][string]$ServiceName,
        [Parameter(Mandatory = $true)][string]$ManagedWebDirectory,
        [AllowEmptyCollection()][string[]]$PreviousWebDirEntries = @()
    )

    $managed = "JELLYFIN_WEB_DIR=$ManagedWebDirectory"
    $current = @(Get-JficServiceEnvironment $ServiceName)

    if (-not ($current -contains $managed)) {
        # The administrator changed this after JFIC was installed. Do not overwrite it.
        return $false
    }

    $updated = @($current | Where-Object { $_ -ne $managed })
    $hasCurrentCustomWebDir = @($updated | Where-Object { $_ -match '^(?i)JELLYFIN_WEB_DIR=' }).Count -gt 0
    if (-not $hasCurrentCustomWebDir) {
        foreach ($entry in @($PreviousWebDirEntries)) {
            if (-not [string]::IsNullOrWhiteSpace($entry) -and -not ($updated -contains $entry)) {
                $updated += $entry
            }
        }
    }

    Set-JficServiceEnvironment -ServiceName $ServiceName -Values $updated
    return $true
}

function Test-JficExplicitWebDirArgument {
    param([AllowNull()][string]$ImagePath)
    if ([string]::IsNullOrWhiteSpace($ImagePath)) { return $false }
    return $ImagePath -match '(?i)(?:^|\s)--webdir(?:=|\s+)'
}

function Test-JficRunningProcessHasExplicitWebDir {
    param([Parameter(Mandatory = $true)][string]$Executable)
    foreach ($process in @(Get-JficJellyfinServerProcesses $Executable)) {
        if (Test-JficExplicitWebDirArgument ([string]$process.CommandLine)) { return $true }
    }
    return $false
}
