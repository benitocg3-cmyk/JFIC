[CmdletBinding()]
param(
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Jfic.Windows.Common.ps1')

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-Failure([string]$Message) { $failures.Add($Message) }
function Add-Warning([string]$Message) { $warnings.Add($Message) }

Write-JficStep 'NVIDIA / FFmpeg preflight'

$nvidia = Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue
if ($null -eq $nvidia) {
    $candidates = @(
        (Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'),
        (Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            $nvidia = [pscustomobject]@{ Source = $candidate }
            break
        }
    }
}

if ($null -eq $nvidia) {
    Add-Failure 'nvidia-smi.exe was not found. Install a compatible NVIDIA driver, or use -SkipNvidiaPreflight when installing JFIC for client-side/software-only use.'
}
else {
    try {
        $gpu = & $nvidia.Source --query-gpu=name,driver_version --format=csv,noheader 2>&1
        Write-Host "  GPU: $($gpu -join '; ')"
    }
    catch {
        Add-Failure "nvidia-smi failed: $($_.Exception.Message)"
    }
}

try {
    $jellyfin = Get-JficJellyfinInfo
    $ffmpeg = Get-JficFfmpeg $jellyfin.InstallFolder
}
catch {
    Add-Failure $_.Exception.Message
    $ffmpeg = $null
}

if ([string]::IsNullOrWhiteSpace($ffmpeg)) {
    Add-Failure 'FFmpeg was not found in the Jellyfin installation or PATH.'
}
else {
    Write-Host "  FFmpeg: $ffmpeg"
    $encoders = (& $ffmpeg -hide_banner -encoders 2>&1 | Out-String)
    foreach ($encoder in @('h264_nvenc', 'hevc_nvenc')) {
        if ($encoders -notmatch [regex]::Escape($encoder)) {
            Add-Failure "Required NVENC encoder is missing: $encoder"
        }
        else {
            Write-Host "  Encoder OK: $encoder"
        }
    }

    if ($encoders -match 'av1_nvenc') {
        Write-Host '  Encoder OK: av1_nvenc'
    }
    else {
        Add-Warning 'av1_nvenc is not present. This is expected on GPUs/FFmpeg builds without AV1 NVENC support.'
    }

    $filters = (& $ffmpeg -hide_banner -filters 2>&1 | Out-String)
    foreach ($filter in @('scale_cuda', 'hwupload_cuda', 'eq', 'hue')) {
        if ($filters -notmatch "(?m)\b$([regex]::Escape($filter))\b") {
            Add-Failure "Required FFmpeg filter is missing: $filter"
        }
        else {
            Write-Host "  Filter OK: $filter"
        }
    }

    if ($filters -match '(?m)\btonemap_cuda\b') {
        Write-Host '  Filter OK: tonemap_cuda'
    }
    else {
        Add-Warning 'tonemap_cuda is not present. JFIC can still operate without that optional filter.'
    }
}

foreach ($warning in $warnings) { Write-JficWarn $warning }

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error "[JFIC] $failure" -ErrorAction Continue }
    if ($Strict) {
        throw "NVIDIA / FFmpeg preflight failed with $($failures.Count) blocking issue(s)."
    }
    return $false
}

Write-JficStep 'NVIDIA / FFmpeg preflight passed.'
return $true
