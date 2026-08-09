# Jellyfin Image Controls — 1.0.0-beta2
<img width="1044" height="1180" alt="JFIC" src="https://github.com/user-attachments/assets/b2cfa7b1-89d5-49b2-bccc-cd9028c335bb" />

JFIC targets Jellyfin Server 10.11.11 and NVIDIA NVENC/NVDEC.

There are two distinct playback scenarios:

- **Direct Play / Direct Stream:** image adjustments are applied in Firefox using CSS/SVG after decoding. No transcoding is requested.
- **Video transcoding already selected by Jellyfin:** Harmony adds the filters to the existing FFmpeg pipeline. JFIC never turns a `copy` video stream into a transcoded stream.

## Simple Installation via Remote Desktop

Copy the ZIP file to `~/jfic-install` on Ubuntu, then open a terminal:

```bash
cd ~/jfic-install
unzip -o JellyfinImageControls-Ubuntu-1.0.0-beta2.zip .
sudo bash install.sh
sudo bash doctor.sh
```

The standard installation installs both the plugin and a JFIC-owned Web overlay.

It does **not** modify `/usr/share/jellyfin/web`, Jellyfin binaries, media files, or `/etc/jellyfin`.

JFIC creates the small systemd drop-in:

```text
/etc/systemd/system/jellyfin.service.d/90-jfic-web.conf
```

This drop-in is used to serve JFIC's Web copy. `uninstall.sh` removes it during uninstallation.

If you only want the server plugin:

```bash
sudo bash install.sh --no-web
```

In this mode, the Harmony backend still works for existing transcodes, but no button can be added automatically to Jellyfin Web.

## Usage

In Firefox, Chrome, or the Android app, start playing a video and click the `palette` button.

Settings are stored locally in the browser and are remembered between sessions.

During Direct Stream playback, image processing is performed locally.

When an existing video transcode is active, the panel indicates whether FFmpeg/NVENC has taken over the processing. Temperature adjustment always remains local.

## Complete JFIC Uninstallation

From the same directory:

```bash
sudo bash uninstall.sh
```

This removes the plugin, `0Harmony.dll`, the JFIC Web overlay, its systemd drop-in, and JFIC state files.

It leaves the official Jellyfin installation, the native Jellyfin Web interface, Jellyfin settings, the database, and all media files untouched.

To also remove the plugin's XML configuration:

```bash
sudo bash uninstall.sh --purge-config
```

## Diagnostics

```bash
sudo bash doctor.sh
sudo bash verify-base.sh
```

The expected log output contains:

```text
JFIC Harmony runtime patch active
```

If Harmony fails, the plugin does not break Jellyfin. The diagnostic tools report the error, and playback continues without server-side image filters.

## Temporary Safe Mode

```bash
sudo bash ffmpeg-safe-mode.sh on
sudo bash ffmpeg-safe-mode.sh status
sudo bash ffmpeg-safe-mode.sh off
```

Safe mode only disables the JFIC FFmpeg hooks after Jellyfin is restarted. Harmony remains installed and available for normal operation.

## Windows Development

```powershell
.\eng\Build.ps1
.\eng\Package-Ubuntu.ps1
```

The ZIP package is generated at:

```text
dist\JellyfinImageControls-Ubuntu-1.0.0-beta2.zip
```
