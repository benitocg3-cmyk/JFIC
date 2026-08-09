[CmdletBinding()]
param(
    [switch]$PurgeConfig,
    [switch]$PurgeBackups,
    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Jfic.Windows.Common.ps1')

Assert-JficAdministrator

$jellyfin = Get-JficJellyfinInfo
$state = Get-JficInstallState
$pluginDirectory = if ($null -ne $state -and -not [string]::IsNullOrWhiteSpace($state.PluginDirectory)) {
    [string]$state.PluginDirectory
}
else {
    Get-JficPluginDirectory $jellyfin.DataFolder
}

$service = $jellyfin.Service
$serviceWasRunning = Stop-JficServiceIfRunning $service

try {
    Write-JficStep 'Removing JFIC plugin directories...'
    $pluginsRoot = Join-Path $jellyfin.DataFolder 'plugins'
    if (Test-Path $pluginsRoot) {
        Get-ChildItem -LiteralPath $pluginsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'Image Controls_*' } |
            Remove-Item -Recurse -Force
    }

    if ($PurgeConfig) {
        $configRoot = Join-Path $pluginsRoot 'configurations'
        if (Test-Path $configRoot) {
            Get-ChildItem -LiteralPath $configRoot -File -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Name -like '*Image Controls*.xml' -or
                    $_.Name -like '*ImageControls*.xml'
                } |
                Remove-Item -Force
        }
        Write-JficStep 'Plugin XML configuration removed.'
    }

    if ($null -ne $state -and
        $null -ne $service -and
        -not [string]::IsNullOrWhiteSpace($state.ManagedWebDir)) {
        $restored = Restore-JficWebServiceEnvironment `
            -ServiceName $service.Name `
            -ManagedWebDirectory ([string]$state.ManagedWebDir) `
            -PreviousWebDirEntries @($state.PreviousWebDirEntries)
        if ($restored) {
            Write-JficStep 'Previous Jellyfin Web service configuration restored.'
        }
        else {
            Write-JficWarn 'The service Web directory had been changed after JFIC installation; it was left untouched.'
        }
    }

    $managedWeb = if ($null -ne $state -and -not [string]::IsNullOrWhiteSpace($state.ManagedWebDir)) {
        [string]$state.ManagedWebDir
    }
    else {
        Get-JficWebOverlayDirectory
    }
    Remove-Item -LiteralPath $managedWeb -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item -LiteralPath $script:JficSafeModeMarker -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:JficStateFile -Force -ErrorAction SilentlyContinue

    if ($PurgeBackups) {
        Remove-Item -LiteralPath (Join-Path $script:JficStateRoot 'backups') -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Remove empty JFIC-owned directories only. Never remove Jellyfin native data.
    foreach ($dir in @((Join-Path $script:JficStateRoot 'current'), $script:JficStateRoot)) {
        if (Test-Path $dir) {
            $child = Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -eq $child) { Remove-Item -LiteralPath $dir -Force -ErrorAction SilentlyContinue }
        }
    }

    if (-not $NoRestart -and $serviceWasRunning -and $null -ne $service) {
        Start-JficServiceAndVerify $service.Name
    }
    elseif ($serviceWasRunning) {
        Write-JficWarn "Jellyfin was running before uninstallation but -NoRestart was selected. Start service '$($service.Name)' manually."
    }

    Write-JficStep 'JFIC uninstalled. Native Jellyfin files, databases, settings and media were not removed.'
}
catch {
    if ($serviceWasRunning -and -not $NoRestart -and $null -ne $service) {
        try { Start-JficServiceAndVerify $service.Name } catch { Write-JficWarn "Jellyfin restart failed: $($_.Exception.Message)" }
    }
    throw
}
