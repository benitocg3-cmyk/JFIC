[CmdletBinding()]
param(
    [switch]$NoWeb,
    [switch]$ForceVersion,
    [switch]$NoRestart,
    [switch]$SkipNvidiaPreflight,
    [switch]$ForceWebOverride
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Jfic.Windows.Common.ps1')

Assert-JficAdministrator

$packageRoot = $PSScriptRoot
$pluginSource = Join-Path $packageRoot 'plugin'
$webSource = Join-Path $packageRoot 'web'
$versionFile = Join-Path $packageRoot 'VERSION'

if (-not (Test-Path (Join-Path $pluginSource 'Jellyfin.Plugin.ImageControls.dll'))) {
    throw "Plugin payload is missing from $pluginSource"
}
if (-not (Test-Path (Join-Path $pluginSource '0Harmony.dll'))) {
    throw "Harmony payload is missing from $pluginSource"
}
if (-not $NoWeb) {
    if (-not (Test-Path (Join-Path $webSource 'image-controls.js')) -or
        -not (Test-Path (Join-Path $webSource 'image-controls.css'))) {
        throw "Web payload is missing from $webSource"
    }
}

$packageVersion = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { 'unknown' }
$jellyfin = Get-JficJellyfinInfo
$pluginDirectory = Get-JficPluginDirectory $jellyfin.DataFolder
$webOverlay = Get-JficWebOverlayDirectory
$previousState = Get-JficInstallState

Write-JficStep "Package version: $packageVersion"
Write-JficStep "Jellyfin executable: $($jellyfin.Executable)"
Write-JficStep "Jellyfin data: $($jellyfin.DataFolder)"
Write-JficStep "Detected Jellyfin version: $($jellyfin.Version)"

if (-not $ForceVersion -and $jellyfin.Version -ne $script:JficTargetJellyfin) {
    throw "JFIC $packageVersion targets Jellyfin $script:JficTargetJellyfin, but $($jellyfin.Version) was detected. Use -ForceVersion only after validating compatibility."
}

$service = $jellyfin.Service
if (-not $NoWeb) {
    if ($null -eq $service) {
        throw 'Automatic Web overlay installation requires Jellyfin to be installed as a Windows service. Use -NoWeb for plugin-only installation, or install Jellyfin as a service.'
    }
    if (-not (Test-Path (Join-Path $jellyfin.NativeWeb 'index.html'))) {
        throw "Native Jellyfin Web was not found at $($jellyfin.NativeWeb)"
    }
    $imagePath = Get-JficServiceImagePath $service.Name
    if (Test-JficExplicitWebDirArgument $imagePath) {
        throw "The Jellyfin service already has an explicit --webdir command-line argument. Jellyfin gives --webdir higher priority than JELLYFIN_WEB_DIR, so JFIC will not modify it automatically. Use -NoWeb or remove the custom --webdir first."
    }
}

if (-not $SkipNvidiaPreflight) {
    $preflightOk = & (Join-Path $packageRoot 'nvidia-preflight.ps1') -Strict
    if (-not $preflightOk) { throw 'NVIDIA / FFmpeg preflight failed.' }
}
else {
    Write-JficWarn 'NVIDIA / FFmpeg preflight skipped by request.'
}

New-Item -ItemType Directory -Path $script:JficStateRoot -Force | Out-Null
$backupRoot = Join-Path $script:JficStateRoot ("backups\" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

$pluginBackup = Join-Path $backupRoot 'plugin'
$webBackup = Join-Path $backupRoot 'web'
$stateBackup = Join-Path $backupRoot 'install-state.json'
$hadPlugin = Test-Path $pluginDirectory
$hadWeb = Test-Path $webOverlay
$hadState = Test-Path $script:JficStateFile

if ($hadPlugin) { Copy-Item -LiteralPath $pluginDirectory -Destination $pluginBackup -Recurse -Force }
if ($hadWeb) { Copy-Item -LiteralPath $webOverlay -Destination $webBackup -Recurse -Force }
if ($hadState) { Copy-Item -LiteralPath $script:JficStateFile -Destination $stateBackup -Force }

$serviceWasRunning = $false
$originalServiceEnvironment = @()
$serviceEnvironmentChanged = $false

try {
    if ($null -ne $service) {
        $originalServiceEnvironment = @(Get-JficServiceEnvironment $service.Name)
        $serviceWasRunning = Stop-JficServiceIfRunning $service
    }
    else {
        $runningProcess = Get-Process -Name 'jellyfin' -ErrorAction SilentlyContinue
        if ($null -ne $runningProcess) {
            throw 'Jellyfin is running outside the Windows service. Stop the tray/direct Jellyfin process before installing JFIC.'
        }
    }

    Write-JficStep "Installing plugin to $pluginDirectory"
    Remove-Item -LiteralPath $pluginDirectory -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $pluginDirectory -Force | Out-Null
    Get-ChildItem -LiteralPath $pluginSource -Force | Copy-Item -Destination $pluginDirectory -Recurse -Force

    $previousWebDirEntries = @()
    $webInstalled = -not $NoWeb

    if ($webInstalled) {
        Write-JficStep "Creating JFIC-owned Web overlay at $webOverlay"
        Remove-Item -LiteralPath $webOverlay -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $webOverlay -Force | Out-Null
        Get-ChildItem -LiteralPath $jellyfin.NativeWeb -Force | Copy-Item -Destination $webOverlay -Recurse -Force
        Copy-Item -LiteralPath (Join-Path $webSource 'image-controls.js') -Destination $webOverlay -Force
        Copy-Item -LiteralPath (Join-Path $webSource 'image-controls.css') -Destination $webOverlay -Force

        $indexPath = Join-Path $webOverlay 'index.html'
        $html = [IO.File]::ReadAllText($indexPath)
        if ($html -notmatch 'data-jfic="1"') {
            if ($html -notmatch '<head>') { throw 'Could not find <head> in Jellyfin Web index.html.' }
            $marker = "<link rel=`"stylesheet`" href=`"image-controls.css?v=$packageVersion`" data-jfic=`"1`">`r`n<script src=`"image-controls.js?v=$packageVersion`" data-jfic=`"1`"></script>"
            $html = [regex]::Replace($html, '<head>', "<head>`r`n$marker", 1)
            $utf8NoBom = New-Object Text.UTF8Encoding($false)
            [IO.File]::WriteAllText($indexPath, $html, $utf8NoBom)
        }

        $previousWebDirEntries = @(Set-JficWebServiceEnvironment `
            -ServiceName $service.Name `
            -WebDirectory $webOverlay `
            -ForceWebOverride:$ForceWebOverride `
            -PreviousState $previousState)
        $serviceEnvironmentChanged = $true
    }
    elseif ($null -ne $previousState -and $null -ne $service -and -not [string]::IsNullOrWhiteSpace($previousState.ManagedWebDir)) {
        Write-JficStep 'Removing the previously managed JFIC Web override because -NoWeb was selected.'
        [void](Restore-JficWebServiceEnvironment `
            -ServiceName $service.Name `
            -ManagedWebDirectory ([string]$previousState.ManagedWebDir) `
            -PreviousWebDirEntries @($previousState.PreviousWebDirEntries))
        $serviceEnvironmentChanged = $true
        Remove-Item -LiteralPath ([string]$previousState.ManagedWebDir) -Recurse -Force -ErrorAction SilentlyContinue
    }

    $state = [ordered]@{
        Schema = 1
        JficVersion = $packageVersion
        TargetJellyfin = $script:JficTargetJellyfin
        InstalledUtc = [DateTime]::UtcNow.ToString('o')
        JellyfinVersion = $jellyfin.Version
        InstallFolder = $jellyfin.InstallFolder
        DataFolder = $jellyfin.DataFolder
        PluginDirectory = $pluginDirectory
        ServiceName = if ($null -ne $service) { $service.Name } else { $null }
        WebInstalled = $webInstalled
        ManagedWebDir = if ($webInstalled) { $webOverlay } else { $null }
        PreviousWebDirEntries = @($previousWebDirEntries)
        SafeModeMarker = $script:JficSafeModeMarker
    }
    Save-JficInstallState $state

    if (-not $NoRestart -and $serviceWasRunning) {
        Start-JficServiceAndVerify $service.Name
    }
    elseif ($serviceWasRunning) {
        Write-JficWarn "Jellyfin was running before installation but -NoRestart was selected. Start service '$($service.Name)' manually."
    }

    Write-JficStep 'Installation completed successfully.'
    Write-Host "  Plugin: $pluginDirectory"
    if ($webInstalled) { Write-Host "  Web overlay: $webOverlay" }
    Write-Host "  State: $script:JficStateFile"
    Write-Host '  Next: run .\doctor.ps1'
}
catch {
    $installError = $_
    Write-JficWarn "Installation failed. Restoring the previous JFIC state: $($installError.Exception.Message)"

    if ($null -ne $service -and $serviceEnvironmentChanged) {
        try { Set-JficServiceEnvironment -ServiceName $service.Name -Values $originalServiceEnvironment } catch { Write-JficWarn $_.Exception.Message }
    }

    try {
        Remove-Item -LiteralPath $pluginDirectory -Recurse -Force -ErrorAction SilentlyContinue
        if ($hadPlugin -and (Test-Path $pluginBackup)) {
            Copy-Item -LiteralPath $pluginBackup -Destination $pluginDirectory -Recurse -Force
        }
    }
    catch { Write-JficWarn "Plugin rollback failed: $($_.Exception.Message)" }

    try {
        Remove-Item -LiteralPath $webOverlay -Recurse -Force -ErrorAction SilentlyContinue
        if ($hadWeb -and (Test-Path $webBackup)) {
            Copy-Item -LiteralPath $webBackup -Destination $webOverlay -Recurse -Force
        }
    }
    catch { Write-JficWarn "Web rollback failed: $($_.Exception.Message)" }

    try {
        if ($hadState -and (Test-Path $stateBackup)) {
            Copy-Item -LiteralPath $stateBackup -Destination $script:JficStateFile -Force
        }
        elseif (-not $hadState) {
            Remove-Item -LiteralPath $script:JficStateFile -Force -ErrorAction SilentlyContinue
        }
    }
    catch { Write-JficWarn "State rollback failed: $($_.Exception.Message)" }

    if ($serviceWasRunning -and -not $NoRestart -and $null -ne $service) {
        try { Start-JficServiceAndVerify $service.Name } catch { Write-JficWarn "Jellyfin restart after rollback failed: $($_.Exception.Message)" }
    }

    throw $installError
}
