# JFIC on Windows Server

This document describes the automated Windows installation shipped with JFIC.

## Supported installation modes

JFIC supports both the Jellyfin **Windows service** installation and the normal **Basic/Tray** installation. Service mode is still a good choice for headless Windows Server systems, but it is no longer required by the JFIC installer. The official Jellyfin Windows installer uses the `JellyfinServer` service name and records the Jellyfin install/data directories in:

```text
HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Jellyfin\Server
```

JFIC uses those values instead of assuming fixed paths. When the `JellyfinServer` service is absent, JFIC detects the official tray executable and treats the installation as Basic/Tray mode.

A typical installation uses:

```text
C:\Program Files\Jellyfin\Server
C:\ProgramData\Jellyfin\Server
```

but the scripts support custom locations exposed by Jellyfin's registry values.

## Install

Extract `JellyfinImageControls-Windows-<version>.zip` and run:

```text
Install-JFIC.cmd
```

The launcher requests Administrator privileges automatically. Validate the result with:

```text
Doctor-JFIC.cmd
```

The equivalent PowerShell commands are:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1
.\doctor.ps1
```

## What the installer changes

The plugin is installed below Jellyfin's data directory:

```text
<DataFolder>\plugins\Image Controls_1.0.0.0
```

JFIC state is stored separately:

```text
%ProgramData%\jellyfin-image-controls
```

The Web overlay is stored at:

```text
%ProgramData%\jellyfin-image-controls\current\web
```

The installer copies the native Jellyfin Web application into that JFIC-owned directory and adds `image-controls.js` and `image-controls.css`.

How Jellyfin is pointed at that copy depends on the detected run mode:

- **Service mode:** JFIC adds `JELLYFIN_WEB_DIR` to the Jellyfin service environment.
- **Basic/Tray mode:** JFIC sets machine-level `JELLYFIN_WEB_DIR`, which is inherited by newly started Jellyfin/tray processes.

The original Jellyfin Web directory is not edited. The installer records the previous value at the relevant scope so it can be restored during uninstallation.

## Transactional behavior

Before replacing an existing JFIC installation, the installer copies the current JFIC plugin/Web state into:

```text
%ProgramData%\jellyfin-image-controls\backups\<timestamp>
```

If installation fails after Jellyfin has been stopped, the script attempts to restore:

- the previous JFIC plugin directory;
- the previous JFIC Web overlay;
- the previous service or machine Web environment;
- the previous JFIC state file;
- the previous Jellyfin running state.

It does not roll back or modify native Jellyfin files because those files are never replaced by the installer.

## Existing custom Web configuration

Jellyfin resolves its Web directory in this order:

1. `--webdir` command-line option;
2. `JELLYFIN_WEB_DIR` environment variable;
3. the `jellyfin-web` directory beside `jellyfin.exe`.

If the Windows service or a running direct Jellyfin process contains an explicit `--webdir`, JFIC stops with an error instead of silently overriding it.

If the relevant service/machine scope already has a custom `JELLYFIN_WEB_DIR`, JFIC also stops by default. To let JFIC temporarily replace that environment value while preserving it for uninstallation, run:

```powershell
.\install.ps1 -ForceWebOverride
```

## NVIDIA preflight

The standard installer runs:

```powershell
.\nvidia-preflight.ps1 -Strict
```

It checks:

- `nvidia-smi`;
- Jellyfin FFmpeg discovery;
- `h264_nvenc`;
- `hevc_nvenc`;
- `scale_cuda`;
- `hwupload_cuda`;
- `eq`;
- `hue`.

`av1_nvenc` and `tonemap_cuda` are reported when available but are not required for every GPU/use case.

For browser-only/software testing:

```powershell
.\install.ps1 -SkipNvidiaPreflight
```

## Safe mode

The runtime patch now resolves the safe-mode marker per operating system.

Windows:

```text
%ProgramData%\jellyfin-image-controls\disable-ffmpeg-patch
```

Linux:

```text
/var/lib/jellyfin-image-controls/disable-ffmpeg-patch
```

An explicit `JFIC_SAFE_MODE_MARKER` environment variable can override the marker path for development/testing.

Use:

```powershell
.\ffmpeg-safe-mode.ps1 on
.\ffmpeg-safe-mode.ps1 status
.\ffmpeg-safe-mode.ps1 off
```

## Basic/Tray mode

The standard Jellyfin Basic Install is fully automated. No Windows service is required.

The installer detects `Jellyfin.Windows.Tray.exe` (and older `JellyfinTray.exe` naming), stops the tray/server when necessary, installs JFIC, configures the machine-level Web environment, and restarts Jellyfin through the tray when it was previously running.

If Jellyfin was already stopped, JFIC leaves it stopped.

## Plugin-only installation

To install only the backend plugin and skip all Web UI integration:

```powershell
.\install.ps1 -NoWeb
```

This works in both service and Basic/Tray modes.

## Uninstall

The easiest removal is:

```text
Uninstall-JFIC.cmd
```

The PowerShell equivalent is:

```powershell
.\uninstall.ps1
```

Optional switches:

```powershell
.\uninstall.ps1 -PurgeConfig
.\uninstall.ps1 -PurgeBackups
.\uninstall.ps1 -NoRestart
```

The uninstaller removes JFIC-owned files and restores the service-level or machine-level Web environment saved during installation. It does not remove native Jellyfin files, databases or media.

## Troubleshooting

Run:

```powershell
.\doctor.ps1
```

The latest Jellyfin logs are normally found below:

```text
<DataFolder>\log
```

Useful JFIC messages include:

```text
JFIC Harmony runtime patch active
JFIC safe mode is enabled
JFIC Harmony runtime patch could not be installed
```

If the Web UI does not show the palette button, check that:

- `doctor.ps1` reports the Web overlay as injected;
- the expected service-level or machine-level `JELLYFIN_WEB_DIR` is present;
- no `--webdir` argument overrides it;
- Jellyfin was restarted after installation;
- the browser cache has been refreshed.
