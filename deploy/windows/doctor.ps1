[CmdletBinding()]
param(
    [switch]$SkipNvidiaPreflight
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'Jfic.Windows.Common.ps1')

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Check-Ok([string]$Message) { Write-Host "[ OK ] $Message" }
function Check-Warn([string]$Message) { $warnings.Add($Message); Write-Warning "[WARN] $Message" }
function Check-Fail([string]$Message) { $failures.Add($Message); Write-Host "[FAIL] $Message" -ForegroundColor Red }

Write-Host 'JFIC Windows doctor'
Write-Host '==================='

try {
    $jellyfin = Get-JficJellyfinInfo
    Check-Ok "Jellyfin executable: $($jellyfin.Executable)"
    if ($jellyfin.Version -eq $script:JficTargetJellyfin) {
        Check-Ok "Jellyfin version: $($jellyfin.Version)"
    }
    else {
        Check-Warn "Jellyfin version is $($jellyfin.Version); JFIC currently targets $script:JficTargetJellyfin."
    }
}
catch {
    Check-Fail $_.Exception.Message
    Write-Host "`nResult: FAILED ($($failures.Count) blocking issue(s))"
    exit 1
}

if ($null -ne $jellyfin.Service) {
    $jellyfin.Service.Refresh()
    if ($jellyfin.Service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
        Check-Ok "Run mode: Windows service '$($jellyfin.Service.Name)' (running)."
    }
    else {
        Check-Warn "Run mode: Windows service '$($jellyfin.Service.Name)' ($($jellyfin.Service.Status))."
    }
}
else {
    $trayProcesses = @(Get-JficTrayProcesses $jellyfin.TrayExecutable)
    $serverProcesses = @(Get-JficJellyfinServerProcesses $jellyfin.Executable)
    if (-not [string]::IsNullOrWhiteSpace($jellyfin.TrayExecutable)) {
        if ($trayProcesses.Count -gt 0) {
            Check-Ok "Run mode: Jellyfin Basic/Tray ($($jellyfin.TrayExecutable), running)."
        }
        else {
            Check-Ok "Run mode: Jellyfin Basic/Tray ($($jellyfin.TrayExecutable))."
        }
    }
    else {
        Check-Warn 'Run mode: direct jellyfin.exe (no Windows service or Jellyfin tray executable detected).'
    }

    if ($serverProcesses.Count -gt 0) {
        Check-Ok "Jellyfin process is running (PID $((@($serverProcesses | Select-Object -ExpandProperty ProcessId)) -join ', '))."
    }
    else {
        Check-Warn 'Jellyfin process is not currently running.'
    }
}

$state = Get-JficInstallState
$pluginDirectory = if ($null -ne $state -and -not [string]::IsNullOrWhiteSpace([string]$state.PluginDirectory)) {
    [string]$state.PluginDirectory
}
else {
    Get-JficPluginDirectory $jellyfin.DataFolder
}
$pluginDll = Join-Path $pluginDirectory 'Jellyfin.Plugin.ImageControls.dll'
$harmonyDll = Join-Path $pluginDirectory '0Harmony.dll'
if (Test-Path $pluginDll) { Check-Ok "Plugin DLL: $pluginDll" } else { Check-Fail "Plugin DLL missing: $pluginDll" }
if (Test-Path $harmonyDll) { Check-Ok "Harmony DLL: $harmonyDll" } else { Check-Fail "Harmony DLL missing: $harmonyDll" }

if ($null -ne $state) {
    Check-Ok "Install state: $script:JficStateFile"
    Write-Host "       JFIC version: $($state.JficVersion)"
    Write-Host "       Installed UTC: $($state.InstalledUtc)"
    if (-not [string]::IsNullOrWhiteSpace([string]$state.RunMode)) {
        Write-Host "       Installed run mode: $($state.RunMode)"
    }
}
else {
    Check-Warn "Install state not found: $script:JficStateFile"
}

if (Test-Path $script:JficSafeModeMarker) {
    Check-Warn "FFmpeg safe mode is ON: $script:JficSafeModeMarker"
}
else {
    Check-Ok 'FFmpeg safe mode is OFF.'
}

if ($null -ne $state -and $state.WebInstalled -eq $true) {
    $web = [string]$state.ManagedWebDir
    $index = Join-Path $web 'index.html'
    if (Test-Path $index) {
        $html = Get-Content $index -Raw -ErrorAction SilentlyContinue
        if ($html -match 'data-jfic="1"') { Check-Ok "Web overlay injected: $web" }
        else { Check-Fail "JFIC marker missing from: $index" }
    }
    else {
        Check-Fail "Web overlay index missing: $index"
    }

    $mode = [string]$state.WebEnvironmentMode
    if ([string]::IsNullOrWhiteSpace($mode)) {
        # Compatibility with state files created by the first Windows automation.
        $mode = if (-not [string]::IsNullOrWhiteSpace([string]$state.ServiceName)) { 'Service' } else { 'Machine' }
    }

    if ($mode -eq 'Service') {
        if ($null -eq $jellyfin.Service) {
            Check-Fail 'The saved JFIC Web configuration expects a Windows service, but no Jellyfin service is currently installed.'
        }
        else {
            $expected = "JELLYFIN_WEB_DIR=$web"
            $environment = @(Get-JficServiceEnvironment $jellyfin.Service.Name)
            if ($environment -contains $expected) {
                Check-Ok 'Jellyfin service points to the JFIC Web overlay.'
            }
            else {
                Check-Fail "Jellyfin service does not contain expected environment entry: $expected"
            }

            $imagePath = Get-JficServiceImagePath $jellyfin.Service.Name
            if (Test-JficExplicitWebDirArgument $imagePath) {
                Check-Fail 'The Jellyfin service has an explicit --webdir argument, which takes precedence over JELLYFIN_WEB_DIR.'
            }
        }
    }
    elseif ($mode -eq 'Machine') {
        $machine = Get-JficMachineWebEnvironment
        if ($machine.Exists -and $machine.Value -eq $web) {
            Check-Ok 'Windows machine environment points Basic/Tray Jellyfin to the JFIC Web overlay.'
        }
        else {
            $actual = if ($machine.Exists) { $machine.Value } else { '<not set>' }
            Check-Fail "Machine-level JELLYFIN_WEB_DIR is '$actual'; expected '$web'."
        }

        if (Test-JficRunningProcessHasExplicitWebDir $jellyfin.Executable) {
            Check-Fail 'The running Jellyfin process has an explicit --webdir argument, which takes precedence over JELLYFIN_WEB_DIR.'
        }
    }
    else {
        Check-Warn "Unknown Web environment mode in install state: '$mode'."
    }
}
else {
    Check-Ok 'Web overlay is not managed by this installation (plugin-only mode or no state file).'
}

if (-not $SkipNvidiaPreflight) {
    Write-Host ''
    try {
        $preflight = & (Join-Path $PSScriptRoot 'nvidia-preflight.ps1')
        if ($preflight) { Check-Ok 'NVIDIA / FFmpeg preflight passed.' }
        else { Check-Warn 'NVIDIA / FFmpeg preflight reported issues.' }
    }
    catch {
        Check-Warn "NVIDIA / FFmpeg preflight could not complete: $($_.Exception.Message)"
    }
}

$logRoot = Join-Path $jellyfin.DataFolder 'log'
if (Test-Path $logRoot) {
    $latest = Get-ChildItem -LiteralPath $logRoot -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -ne $latest) {
        Write-Host "`nLatest Jellyfin log: $($latest.FullName)"
        $matches = @(Select-String -Path $latest.FullName -Pattern 'JFIC|Image Controls|Harmony runtime patch' -ErrorAction SilentlyContinue |
            Select-Object -Last 8)
        if ($matches.Count -gt 0) {
            foreach ($match in $matches) { Write-Host "  $($match.Line)" }
        }
        else {
            Check-Warn 'No recent JFIC/Harmony lines were found in the latest Jellyfin log.'
        }
    }
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "Result: FAILED ($($failures.Count) blocking issue(s), $($warnings.Count) warning(s))"
    exit 1
}

Write-Host "Result: OK ($($warnings.Count) warning(s))"
exit 0
