[CmdletBinding()]
param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Version = (Get-Content (Join-Path $Root 'VERSION') -Raw).Trim()

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'Build.ps1') -Configuration Release
}

$BuildOut = Join-Path $Root 'src\Jellyfin.Plugin.ImageControls\bin\Release\net9.0'
$PluginDll = Join-Path $BuildOut 'Jellyfin.Plugin.ImageControls.dll'
$HarmonyDll = Join-Path $BuildOut '0Harmony.dll'
if (-not (Test-Path $PluginDll)) { throw "Plugin build output is missing: $PluginDll" }

# Always package the exact net9 Harmony asset referenced by the project. This
# prevents a stale bin/0Harmony.dll from an older package restore being shipped.
$ProjectXml = [xml](Get-Content (Join-Path $Root 'src\Jellyfin.Plugin.ImageControls\Jellyfin.Plugin.ImageControls.csproj') -Raw)
$HarmonyPackageVersion = @(
    $ProjectXml.Project.ItemGroup.PackageReference |
        Where-Object Include -eq 'Lib.Harmony' |
        Select-Object -First 1 -ExpandProperty Version
)
if ([string]::IsNullOrWhiteSpace($HarmonyPackageVersion)) {
    throw 'Lib.Harmony version was not found in Jellyfin.Plugin.ImageControls.csproj.'
}

$NuGetRoot = if ($env:NUGET_PACKAGES) { $env:NUGET_PACKAGES } else { Join-Path $env:USERPROFILE '.nuget\packages' }
$HarmonyPackageDll = Join-Path $NuGetRoot "lib.harmony\$HarmonyPackageVersion\lib\net9.0\0Harmony.dll"
if (-not (Test-Path $HarmonyPackageDll)) { throw "Harmony NuGet asset is missing: $HarmonyPackageDll" }
Copy-Item -LiteralPath $HarmonyPackageDll -Destination $HarmonyDll -Force

$PluginAssembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $PluginDll))
$HarmonyReference = $PluginAssembly.GetReferencedAssemblies() |
    Where-Object Name -eq '0Harmony' |
    Select-Object -First 1
$HarmonyFile = [Reflection.AssemblyName]::GetAssemblyName((Resolve-Path $HarmonyDll))
if ($null -eq $HarmonyReference) { throw 'Jellyfin.Plugin.ImageControls.dll does not reference 0Harmony.' }
if ($HarmonyReference.Version -ne $HarmonyFile.Version) {
    throw "Harmony mismatch: plugin reference=$($HarmonyReference.Version), packaged file=$($HarmonyFile.Version). Run a clean restore/build."
}
Write-Host "Harmony coherent: $($HarmonyFile.Version)"

$Dist = Join-Path $Root 'dist'
$BundleName = "JellyfinImageControls-Windows-$Version"
$Stage = Join-Path $Dist $BundleName
$Zip = Join-Path $Dist "$BundleName.zip"

Remove-Item $Stage -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $Zip -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $Stage 'plugin'), (Join-Path $Stage 'web') | Out-Null

Copy-Item $PluginDll (Join-Path $Stage 'plugin')
Copy-Item $HarmonyDll (Join-Path $Stage 'plugin')
$Pdb = [IO.Path]::ChangeExtension($PluginDll, '.pdb')
if (Test-Path $Pdb) { Copy-Item $Pdb (Join-Path $Stage 'plugin') }

Copy-Item (Join-Path $Root 'web\image-controls.js') (Join-Path $Stage 'web')
Copy-Item (Join-Path $Root 'web\image-controls.css') (Join-Path $Stage 'web')
Copy-Item (Join-Path $Root 'deploy\windows\*.ps1') $Stage
Copy-Item (Join-Path $Root 'deploy\windows\*.cmd') $Stage
Copy-Item (Join-Path $Root 'VERSION') $Stage
Copy-Item (Join-Path $Root 'README.md') $Stage
Copy-Item (Join-Path $Root 'docs\WINDOWS-SERVER.md') (Join-Path $Stage 'INSTALLATION.md')

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$Archive = [IO.Compression.ZipFile]::Open($Zip, [IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem -Path $Stage -Recurse -File | ForEach-Object {
        $RelativePath = $_.FullName.Substring($Stage.Length).TrimStart('\', '/')
        $EntryName = $RelativePath -replace '\\', '/'
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $Archive,
            $_.FullName,
            $EntryName,
            [IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
}
finally {
    $Archive.Dispose()
}

$Hash = (Get-FileHash $Zip -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -Path "$Zip.sha256" -Value "$Hash $([IO.Path]::GetFileName($Zip))" -Encoding ascii
Write-Host "Windows bundle created: $Zip"
Write-Host "SHA256: $Hash"
