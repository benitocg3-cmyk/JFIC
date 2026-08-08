[CmdletBinding()]
param(
    [ValidateSet('Debug','Release')][string]$Configuration = 'Release'
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Push-Location $Root
try {
    Write-Host "== JFIC restore =="
    dotnet restore .\JellyfinImageControls.sln
    Write-Host "== JFIC build ($Configuration) =="
    dotnet build .\JellyfinImageControls.sln -c $Configuration --no-restore
    Write-Host "== JFIC tests =="
    dotnet test .\tests\Jellyfin.Plugin.ImageControls.Tests\Jellyfin.Plugin.ImageControls.Tests.csproj -c $Configuration --no-build
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) {
        node --check .\web\image-controls.js
        node .\tests\web-smoke.mjs
    } else {
        Write-Warning "Node.js absent: tests JS ignorés. Le Web JFIC n'a pas besoin de Node en production."
    }
    Write-Host "Build OK."
} finally { Pop-Location }
