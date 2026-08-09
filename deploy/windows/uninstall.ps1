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
$pluginDirectory = if ($null -ne $state -and -not [string]::IsNullOrWhiteSpace([string]$state.PluginDirectory)) {
    [string]$state.PluginDirectory
}
else {
    Get-JficPluginDirectory $jellyfin.DataFolder
}

$service = $jellyfin.Service
$serviceWasRunning = $false
$runtimeState = $null

if ($null -ne $service) {
    $serviceWasRunning = Stop-JficServiceIfRunning $service
}
else {
    $runtimeState = Stop-JficExecutableRuntime $jellyfin
}

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

    if ($null -ne $state -and -not [string]::IsNullOrWhiteSpace([string]$state.ManagedWebDir)) {
        $mode = [string]$state.WebEnvironmentMode
        if ([string]::IsNullOrWhiteSpace($mode)) {
            $mode = if (-not [string]::IsNullOrWhiteSpace([string]$state.ServiceName)) { 'Service' } else { 'Machine' }
        }

        if ($mode -eq 'Service' -and $null -ne $service) {
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
        elseif ($mode -eq 'Machine') {
            $restored = Restore-JficWebMachineEnvironment `
                -ManagedWebDirectory ([string]$state.ManagedWebDir) `
                -PreviousExists ([bool]$state.PreviousMachineWebDirExists) `
                -PreviousValue ([string]$state.PreviousMachineWebDirValue)
            if ($restored) {
                Write-JficStep 'Previous machine-level Jellyfin Web environment restored.'
            }
            else {
                Write-JficWarn 'The machine-level JELLYFIN_WEB_DIR was changed after JFIC installation; it was left untouched.'
            }
        }
        elseif ($mode -eq 'Service') {
            Write-JficWarn 'The saved Web override belongs to a Jellyfin service that is no longer present; service environment restoration was skipped.'
        }
    }

    $managedWeb = if ($null -ne $state -and -not [string]::IsNullOrWhiteSpace([string]$state.ManagedWebDir)) {
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

    foreach ($dir in @((Join-Path $script:JficStateRoot 'current'), $script:JficStateRoot)) {
        if (Test-Path $dir) {
            $child = Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -eq $child) { Remove-Item -LiteralPath $dir -Force -ErrorAction SilentlyContinue }
        }
    }

    if (-not $NoRestart) {
        if ($serviceWasRunning -and $null -ne $service) {
            Start-JficServiceAndVerify $service.Name
        }
        elseif ($null -eq $service -and $null -ne $runtimeState) {
            Start-JficExecutableRuntime -Jellyfin $jellyfin -RuntimeState $runtimeState
        }
    }
    else {
        if ($serviceWasRunning -and $null -ne $service) {
            Write-JficWarn "Jellyfin was running before uninstallation but -NoRestart was selected. Start service '$($service.Name)' manually."
        }
        elseif ($null -eq $service -and $null -ne $runtimeState -and ($runtimeState.ServerWasRunning -or $runtimeState.TrayWasRunning)) {
            Write-JficWarn 'Jellyfin was running before uninstallation but -NoRestart was selected. Restart Jellyfin/the tray application manually.'
        }
    }

    Write-JficStep 'JFIC uninstalled. Native Jellyfin files, databases, settings and media were not removed.'
}
catch {
    if (-not $NoRestart) {
        if ($serviceWasRunning -and $null -ne $service) {
            try { Start-JficServiceAndVerify $service.Name } catch { Write-JficWarn "Jellyfin restart failed: $($_.Exception.Message)" }
        }
        elseif ($null -eq $service -and $null -ne $runtimeState) {
            try { Start-JficExecutableRuntime -Jellyfin $jellyfin -RuntimeState $runtimeState } catch { Write-JficWarn "Jellyfin restart failed: $($_.Exception.Message)" }
        }
    }
    throw
}
