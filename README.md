# Jellyfin Image Controls — 1.0.0-beta2

<img width="1044" height="1180" alt="JFIC" src="https://github.com/user-attachments/assets/b2cfa7b1-89d5-49b2-bccc-cd9028c335bb" />

JFIC (**Jellyfin Image Controls**) adds runtime image controls to Jellyfin without modifying media files and without forcing video transcoding just to apply an adjustment.

Current target:

- **Jellyfin Server:** 10.11.11
- **.NET:** 9.0
- **Harmony:** 2.4.2
- **Primary hardware path:** NVIDIA NVENC/NVDEC
- **Supported server installers in this repository:** Ubuntu and Windows Server

> [!IMPORTANT]
> JFIC patches Jellyfin internals at runtime with Harmony. Version `1.0.0-beta2` targets Jellyfin `10.11.11` specifically. Do not assume compatibility with another Jellyfin release without testing it first.

## How it works

JFIC deliberately separates two playback cases:

- **Direct Play / Direct Stream:** image adjustments are applied in the Web client using CSS/SVG after decoding. JFIC does not request transcoding.
- **Video transcoding already selected by Jellyfin:** Harmony appends JFIC filters to the existing FFmpeg pipeline. JFIC refuses to turn a video-copy path into a video transcode.

The invariant is simple:

```text
never-force-video-transcode
```

Available controls:

- brightness
- contrast
- saturation
- hue
- gamma
- color temperature

Color temperature currently remains client-side.

---

# Windows Server — automated installation

Windows Server no longer requires manually copying DLLs or editing Jellyfin Web files.

## Requirements

- Jellyfin Server `10.11.11`
- Jellyfin installed either in **Windows service mode** or the normal **Basic/Tray mode**
- PowerShell 5.1 or newer
- Administrator rights
- for the NVIDIA server-side path: a working NVIDIA driver and Jellyfin FFmpeg with NVENC/CUDA support

The official Jellyfin Windows installer normally exposes its `InstallFolder` and `DataFolder` through the Windows Registry. JFIC discovers those values automatically and also detects whether Jellyfin is running as a service or through the Windows tray application.

## Install

Download and extract:

```text
JellyfinImageControls-Windows-1.0.0-beta2.zip
```

For the easiest installation, simply run:

```text
Install-JFIC.cmd
```

The launcher requests Administrator privileges through UAC automatically. After installation, run:

```text
Doctor-JFIC.cmd
```

PowerShell users can run the same workflow directly:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1
.\doctor.ps1
```

That is the normal Windows Server installation.

The installer automatically:

1. detects the Jellyfin installation and data directories;
2. verifies the Jellyfin version;
3. runs the NVIDIA / FFmpeg preflight;
4. detects **Service**, **Basic/Tray**, or direct executable mode;
5. stops Jellyfin only when needed for a running installation;
6. installs `Jellyfin.Plugin.ImageControls.dll` and the exact packaged `0Harmony.dll`;
7. creates a JFIC-owned copy of Jellyfin Web;
8. injects `image-controls.js` and `image-controls.css` into that copy;
9. configures `JELLYFIN_WEB_DIR` at service scope for service installs, or machine scope for Basic/Tray installs;
10. saves the previous Web environment and installation state for clean uninstallation/upgrades;
11. restarts Jellyfin using the same run mode when it had been running before installation.

JFIC does **not** modify the native `jellyfin-web` directory.

### Installer options

```powershell
.\install.ps1 -NoWeb
.\install.ps1 -SkipNvidiaPreflight
.\install.ps1 -ForceVersion
.\install.ps1 -NoRestart
.\install.ps1 -ForceWebOverride
```

`-NoWeb` installs only the server plugin. Harmony can still operate during an existing video transcode, but JFIC cannot automatically add its palette button to Jellyfin Web.

`-SkipNvidiaPreflight` is useful for client-side/software-only testing or systems where NVIDIA acceleration is intentionally unavailable.

`-ForceVersion` bypasses the exact Jellyfin `10.11.11` check. Use it only after validating the runtime hooks against that Jellyfin build.

`-ForceWebOverride` allows JFIC to temporarily replace an existing `JELLYFIN_WEB_DIR` at the scope used by the detected Jellyfin mode. The previous value is saved and restored by the uninstaller. JFIC still refuses to override an explicit `--webdir` command-line argument because that argument has higher precedence.

## Diagnostics

Run:

```powershell
.\doctor.ps1
```

The doctor checks the Jellyfin version, detected Windows run mode, plugin DLL, Harmony DLL, installation state, Web overlay, safe mode, service/machine Web configuration, NVIDIA/FFmpeg capabilities, and recent JFIC/Harmony log entries.

To skip the GPU checks:

```powershell
.\doctor.ps1 -SkipNvidiaPreflight
```

## Temporary FFmpeg safe mode

Safe mode prevents the Harmony FFmpeg hooks from being installed when Jellyfin starts.

```powershell
.\ffmpeg-safe-mode.ps1 on
.\ffmpeg-safe-mode.ps1 status
.\ffmpeg-safe-mode.ps1 off
```

If Jellyfin is running, the script restarts it automatically using the detected Service or Basic/Tray mode so the change takes effect.

## Uninstall

For the easiest removal, run:

```text
Uninstall-JFIC.cmd
```

Or from an elevated PowerShell:

```powershell
.\uninstall.ps1
```

The uninstaller removes JFIC, removes its Web overlay, restores the previous service-level or machine-level Jellyfin Web configuration, and leaves the native Jellyfin installation, database, settings, and media untouched.

Optional cleanup:

```powershell
.\uninstall.ps1 -PurgeConfig
.\uninstall.ps1 -PurgeBackups
```

## Windows Basic/Tray installs

The normal Jellyfin **Basic Install** is supported automatically. A Windows service is not required.

When no `JellyfinServer` service exists, JFIC:

- detects the official Jellyfin tray executable;
- creates the same isolated Web overlay used in service mode;
- stores `JELLYFIN_WEB_DIR` in the Windows machine environment so newly started Jellyfin processes use that overlay;
- preserves any previous machine-level value and restores it during uninstall;
- restarts the tray/server automatically if Jellyfin was running before installation.

The installer never edits the native `jellyfin-web` directory.

Direct `jellyfin.exe` launches are also supported when no tray executable is available.

For the complete Windows procedure and troubleshooting notes, see [`docs/WINDOWS-SERVER.md`](docs/WINDOWS-SERVER.md).

---

# Ubuntu — automated installation

Copy the Ubuntu ZIP to the server, extract it, and run:

```bash
unzip -o JellyfinImageControls-Ubuntu-1.0.0-beta2.zip
cd JellyfinImageControls-Ubuntu-1.0.0-beta2
sudo bash install.sh
sudo bash doctor.sh
```

The standard installation installs both the server plugin and a JFIC-owned Web overlay. It does **not** modify `/usr/share/jellyfin/web`, Jellyfin binaries, media files, or `/etc/jellyfin`.

Plugin-only mode:

```bash
sudo bash install.sh --no-web
```

Uninstall:

```bash
sudo bash uninstall.sh
```

Safe mode:

```bash
sudo bash ffmpeg-safe-mode.sh on
sudo bash ffmpeg-safe-mode.sh status
sudo bash ffmpeg-safe-mode.sh off
```

Diagnostics:

```bash
sudo bash doctor.sh
sudo bash verify-base.sh
```

---

# Usage

After installing the plugin and Web overlay:

1. open Jellyfin in a supported Web-based client;
2. start a video;
3. click the **palette** button;
4. adjust the image controls.

Settings are stored locally in the browser and remembered between sessions.

During Direct Play / Direct Stream, processing remains local to the client. When Jellyfin is already video-transcoding, the panel indicates whether the FFmpeg/NVENC backend has taken over supported adjustments.

If the Harmony runtime patch cannot be installed, JFIC is designed to let playback continue without server-side image filtering instead of deliberately breaking playback.

---

# Jellyfin Desktop / MPV

The JFIC server cannot directly change a `libmpv` instance running on another machine.

The Web client emits an adapter message that a Jellyfin Desktop integration can translate to MPV properties:

```text
brightness -> brightness
contrast   -> contrast
saturation -> saturation
hue        -> hue
gamma      -> gamma
```

Color temperature requires a separate shader or client-side implementation.

See [`clients/jellyfin-desktop/README.md`](clients/jellyfin-desktop/README.md).

---

# Development

Build and test:

```powershell
.\eng\Build.ps1
```

Build a Windows package:

```powershell
.\eng\Package-Windows.ps1
```

Build an Ubuntu package:

```powershell
.\eng\Package-Ubuntu.ps1
```

On Windows, double-clicking or running:

```text
Build-Release.cmd
```

builds/tests once and then creates **both** release packages:

```text
dist\JellyfinImageControls-Ubuntu-1.0.0-beta2.zip
dist\JellyfinImageControls-Windows-1.0.0-beta2.zip
```

Each package also receives a `.sha256` file.

The packaging scripts verify that the shipped `0Harmony.dll` assembly version exactly matches the Harmony reference in `Jellyfin.Plugin.ImageControls.dll`.

---

# Safety guarantees

JFIC is designed around these rules:

- never modify media files;
- never replace Jellyfin server binaries;
- never force a video transcode only to apply image controls;
- leave Direct Play / Direct Stream negotiation alone;
- add server-side filters only after Jellyfin has already selected video transcoding;
- continue playback without server filtering if the runtime patch fails;
- keep the JFIC Web overlay separate from native Jellyfin Web;
- make installation reversible on both Ubuntu and Windows Server.

---

# Current limitations

- Harmony hooks currently target Jellyfin `10.11.11`.
- NVIDIA NVENC/NVDEC is the primary accelerated server path.
- Color temperature remains client-side.
- Jellyfin Desktop native MPV control requires a client adapter.
- Automatic Windows Web-overlay management requires Jellyfin Windows service mode.
- A pre-existing service `--webdir` command-line argument must be handled manually because it has higher precedence than `JELLYFIN_WEB_DIR`.

---

# Version

```text
JFIC             1.0.0-beta2
Plugin ABI       1.0.0.0
Target Jellyfin  10.11.11
.NET             9.0
Harmony          2.4.2
```
