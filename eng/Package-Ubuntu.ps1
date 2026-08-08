[CmdletBinding()]
param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Version = (Get-Content (Join-Path $Root 'VERSION') -Raw).Trim()
if (-not $SkipBuild) { & (Join-Path $PSScriptRoot 'Build.ps1') -Configuration Release }

$BuildOut = Join-Path $Root 'src\Jellyfin.Plugin.ImageControls\bin\Release\net9.0'
$PluginDll = Join-Path $BuildOut 'Jellyfin.Plugin.ImageControls.dll'
$HarmonyDll = Join-Path $BuildOut '0Harmony.dll'
if (-not (Test-Path $PluginDll)) { throw "Plugin compile absent: $PluginDll" }

# Always copy the exact net9 asset from the restored package. This repairs a
# stale bin/0Harmony.dll left behind by an earlier Harmony package version.
$ProjectXml = [xml](Get-Content (Join-Path $Root 'src\Jellyfin.Plugin.ImageControls\Jellyfin.Plugin.ImageControls.csproj') -Raw)
$HarmonyPackageVersion = @($ProjectXml.Project.ItemGroup.PackageReference | Where-Object Include -eq 'Lib.Harmony' | Select-Object -First 1 -ExpandProperty Version)
if ([string]::IsNullOrWhiteSpace($HarmonyPackageVersion)) { throw 'Version Lib.Harmony introuvable dans le csproj.' }
$NuGetRoot = if ($env:NUGET_PACKAGES) { $env:NUGET_PACKAGES } else { Join-Path $env:USERPROFILE '.nuget\packages' }
$HarmonyPackageDll = Join-Path $NuGetRoot "lib.harmony\$HarmonyPackageVersion\lib\net9.0\0Harmony.dll"
if (-not (Test-Path $HarmonyPackageDll)) { throw "Asset Harmony NuGet introuvable: $HarmonyPackageDll" }
Copy-Item -LiteralPath $HarmonyPackageDll -Destination $HarmonyDll -Force
if (-not (Test-Path $HarmonyDll)) { throw "0Harmony.dll absent from build output: $HarmonyDll" }

# NuGet can leave an older copy in bin/ after a Harmony package change. Catch
# that before packaging: the plugin reference and the file copied to Ubuntu
# must advertise the exact same assembly version.
$PluginAssembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $PluginDll))
$HarmonyReference = $PluginAssembly.GetReferencedAssemblies() | Where-Object Name -eq '0Harmony' | Select-Object -First 1
$HarmonyFile = [Reflection.AssemblyName]::GetAssemblyName((Resolve-Path $HarmonyDll))
if ($null -eq $HarmonyReference) { throw 'Jellyfin.Plugin.ImageControls.dll ne reference pas 0Harmony.' }
if ($HarmonyReference.Version -ne $HarmonyFile.Version) {
    throw "Harmony incoherent: plugin reference=$($HarmonyReference.Version), fichier=$($HarmonyFile.Version). Relancez une restauration/build propre."
}
Write-Host "Harmony coherent: $($HarmonyFile.Version)"

$Dist = Join-Path $Root 'dist'
$BundleName = "JellyfinImageControls-Ubuntu-$Version"
$Stage = Join-Path $Dist $BundleName
$Zip = Join-Path $Dist "$BundleName.zip"
Remove-Item $Stage -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $Zip -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $Stage 'plugin'), (Join-Path $Stage 'web') | Out-Null

Copy-Item $PluginDll (Join-Path $Stage 'plugin')
Copy-Item $HarmonyDll (Join-Path $Stage 'plugin')
$Pdb = [IO.Path]::ChangeExtension($PluginDll, '.pdb')
if (Test-Path $Pdb) { Copy-Item $Pdb (Join-Path $Stage 'plugin') }
# The browser client is installed into a JFIC-owned Web overlay by install.sh.
Copy-Item (Join-Path $Root 'web\image-controls.js') (Join-Path $Stage 'web')
Copy-Item (Join-Path $Root 'web\image-controls.css') (Join-Path $Stage 'web')
Copy-Item (Join-Path $Root 'deploy\ubuntu\*.sh') $Stage
Copy-Item (Join-Path $Root 'VERSION') $Stage
Copy-Item (Join-Path $Root 'docs\UBUNTU-SAFE-INSTALL.md') (Join-Path $Stage 'INSTALLATION.md')

# Build POSIX ZIP entry names. Compress-Archive writes Windows backslashes.
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
Set-Content -Path "$Zip.sha256" -Value "$Hash  $([IO.Path]::GetFileName($Zip))" -Encoding ascii
Write-Host "Bundle Ubuntu cree: $Zip"
Write-Host "SHA256: $Hash"
