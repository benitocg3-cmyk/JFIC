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
function Check-Fail([string]$Message) { $failures.Add($Message); Write-Error "[FAIL] $Message" -ErrorAction Continue }

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
        Check-Ok "Windows service '$($jellyfin.Service.Name)' is running."
    }
    else {
        Check-Warn "Windows service '$($jellyfin.Service.Name)' is $($jellyfin.Service.Status)."
    }
}
else {
    Check-Warn 'Jellyfin Windows service was not found. Automatic Web overlay management requires service mode.'
}

$pluginDirectory = Get-JficPluginDirectory $jellyfin.DataFolder
$pluginDll = Join-Path $pluginDirectory 'Jellyfin.Plugin.ImageControls.dll'
$harmonyDll = Join-Path $pluginDirectory '0Harmony.dll'
if (Test-Path $pluginDll) { Check-Ok "Plugin DLL: $pluginDll" } else { Check-Fail "Plugin DLL missing: $pluginDll" }
if (Test-Path $harmonyDll) { Check-Ok "Harmony DLL: $harmonyDll" } else { Check-Fail "Harmony DLL missing: $harmonyDll" }

$state = Get-JficInstallState
if ($null -ne $state) {
    Check-Ok "Install state: $script:JficStateFile"
    Write-Host "       JFIC version: $($state.JficVersion)"
    Write-Host "       Installed UTC: $($state.InstalledUtc)"
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

    if ($null -ne $jellyfin.Service) {
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
        $matches = Select-String -Path $latest.FullName -Pattern 'JFIC|Image Controls|Harmony runtime patch' -ErrorAction SilentlyContinue |
            Select-Object -Last 8
        if ($null -ne $matches) {
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
