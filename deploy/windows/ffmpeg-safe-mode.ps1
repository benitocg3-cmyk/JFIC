[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('on', 'off', 'status')]
    [string]$Action = 'status',
    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Jfic.Windows.Common.ps1')

if ($Action -eq 'status') {
    if (Test-Path $script:JficSafeModeMarker) {
        Write-Host "JFIC FFmpeg safe mode: ON ($script:JficSafeModeMarker)"
    }
    else {
        Write-Host 'JFIC FFmpeg safe mode: OFF'
    }
    return
}

Assert-JficAdministrator
$jellyfin = Get-JficJellyfinInfo
$service = $jellyfin.Service
$serviceWasRunning = $false

if ($null -ne $service) {
    $serviceWasRunning = Stop-JficServiceIfRunning $service
}
elseif ($null -ne (Get-Process -Name 'jellyfin' -ErrorAction SilentlyContinue)) {
    throw 'Jellyfin is running outside the Windows service. Stop it manually before changing safe mode.'
}

if ($Action -eq 'on') {
    New-Item -ItemType Directory -Path $script:JficStateRoot -Force | Out-Null
    New-Item -ItemType File -Path $script:JficSafeModeMarker -Force | Out-Null
    Write-JficStep "FFmpeg safe mode enabled: $script:JficSafeModeMarker"
}
else {
    Remove-Item -LiteralPath $script:JficSafeModeMarker -Force -ErrorAction SilentlyContinue
    Write-JficStep 'FFmpeg safe mode disabled.'
}

if (-not $NoRestart -and $serviceWasRunning -and $null -ne $service) {
    Start-JficServiceAndVerify $service.Name
}
elseif ($serviceWasRunning) {
    Write-JficWarn "Restart service '$($service.Name)' to apply the safe-mode change."
}
elseif ($null -eq $service) {
    Write-JficWarn 'Restart Jellyfin manually to apply the safe-mode change.'
}
