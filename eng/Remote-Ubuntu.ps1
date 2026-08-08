[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$HostName,
    [Parameter(Mandatory=$true)][string]$User,
    [ValidateSet('Install','NvidiaPreflight','Doctor','Verify','SafeModeOn','SafeModeOff','SafeModeStatus','Uninstall')][string]$Action = 'Install',
    [int]$Port = 22,
    [switch]$SkipBuild,
    [switch]$ForceVersion,
    [switch]$PurgeBackups
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Version = (Get-Content (Join-Path $Root 'VERSION') -Raw).Trim()
$BundleName = "JellyfinImageControls-Ubuntu-$Version"
$Zip = Join-Path $Root "dist\$BundleName.zip"

foreach ($exe in @('ssh','scp')) {
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) {
        throw "$exe est introuvable. Activez le client OpenSSH de Windows 11."
    }
}

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'Package-Ubuntu.ps1')
}
if (-not (Test-Path $Zip)) { throw "Bundle introuvable: $Zip" }

$Hash = (Get-FileHash $Zip -Algorithm SHA256).Hash.ToLowerInvariant()
$RemoteId = "jfic-$Version-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
$RemoteDir = "/tmp/$RemoteId"
$RemoteZip = "$RemoteDir/$BundleName.zip"
$Target = "$User@$HostName"

# Ask for the password in the terminal and do not let an SSH-agent key win
# before password authentication.
$SshOptions = @(
    '-p', [string]$Port,
    '-o', 'BatchMode=no',
    '-o', 'PreferredAuthentications=password,keyboard-interactive,publickey',
    '-o', 'ConnectTimeout=15'
)
$ScpOptions = @(
    '-P', [string]$Port,
    '-o', 'BatchMode=no',
    '-o', 'PreferredAuthentications=password,keyboard-interactive,publickey',
    '-o', 'ConnectTimeout=15'
)

Write-Host "== Upload $BundleName vers $Target =="
& ssh @SshOptions $Target "mkdir -p '$RemoteDir'"
if ($LASTEXITCODE -ne 0) { throw 'Creation du repertoire temporaire distant echouee.' }
& scp @ScpOptions $Zip "${Target}:$RemoteZip"
if ($LASTEXITCODE -ne 0) { throw 'Upload SCP echoue.' }

$extract = "set -e; cd '$RemoteDir'; echo '$Hash  $BundleName.zip' | sha256sum -c -; python3 -m zipfile -e '$BundleName.zip' package; test -f package/plugin/Jellyfin.Plugin.ImageControls.dll; test -f package/plugin/0Harmony.dll"
& ssh @SshOptions $Target $extract
if ($LASTEXITCODE -ne 0) { throw 'Verification ou extraction distante echouee.' }

if ($Action -ne 'Install' -and $ForceVersion) {
    throw '-ForceVersion est valide uniquement avec -Action Install.'
}
if ($Action -ne 'Uninstall' -and $PurgeBackups) {
    throw '-PurgeBackups est valide uniquement avec -Action Uninstall.'
}

$script = switch ($Action) {
    'Install' {
        $flags = @()
        if ($ForceVersion) { $flags += '--force-version' }
        "install.sh $($flags -join ' ')"
    }
    'NvidiaPreflight' { 'nvidia-preflight.sh --strict' }
    'Doctor' { 'doctor.sh' }
    'Verify' { 'verify-base.sh' }
    'SafeModeOn' { 'ffmpeg-safe-mode.sh on' }
    'SafeModeOff' { 'ffmpeg-safe-mode.sh off' }
    'SafeModeStatus' { 'ffmpeg-safe-mode.sh status' }
    'Uninstall' {
        $flags = @()
        if ($PurgeBackups) { $flags += '--purge-backups' }
        "uninstall.sh $($flags -join ' ')"
    }
}

try {
    Write-Host "== $Action sur $Target =="
    # -tt gives sudo a real terminal for its password prompt.
    & ssh '-tt' @SshOptions $Target "cd '$RemoteDir/package' && sudo -v && sudo bash $script"
    if ($LASTEXITCODE -ne 0) { throw "Action distante $Action echouee (code $LASTEXITCODE)." }
}
finally {
    & ssh @SshOptions $Target "rm -rf '$RemoteDir'" | Out-Null
}

Write-Host "Action $Action terminee. Les fichiers temporaires distants ont ete supprimes."
