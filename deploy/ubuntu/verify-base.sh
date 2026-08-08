#!/usr/bin/env bash
set -u

PLUGIN_ROOT="/var/lib/jellyfin/plugins"
PLUGIN_DIR="$PLUGIN_ROOT/Image Controls_1.0.0.0"
rc=0

echo "=== Verification JFIC ==="
if [[ -f "$PLUGIN_DIR/Jellyfin.Plugin.ImageControls.dll" ]]; then
  [[ -f "$PLUGIN_DIR/0Harmony.dll" ]] || { echo "ERREUR 0Harmony.dll absente" >&2; exit 1; }
  echo "OK plugin JFIC + Harmony"
else
  echo "ABSENT plugin JFIC"
  rc=1
fi

if [[ -f /usr/bin/jellyfin ]]; then echo "OK /usr/bin/jellyfin present (non modifie par JFIC)"; else echo "ATTENTION /usr/bin/jellyfin absent"; rc=1; fi
if [[ -f /usr/share/jellyfin/web/index.html ]]; then echo "OK Web Jellyfin officiel present (non remplace par JFIC)"; else echo "ATTENTION Web Jellyfin officiel absent"; rc=1; fi
if [[ -e /etc/systemd/system/jellyfin.service.d/90-jfic-web.conf ]]; then
  echo "OK overlay Web JFIC present (drop-in JFIC-owned)"
else
  echo "INFO overlay Web JFIC absent (mode plugin seul)"
fi

exit "$rc"
