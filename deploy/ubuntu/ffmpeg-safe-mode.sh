#!/usr/bin/env bash
set -euo pipefail

MARKER="/var/lib/jellyfin-image-controls/disable-ffmpeg-patch"
ACTION="${1:-status}"
case "$ACTION" in
  on)
    [[ $EUID -eq 0 ]] || { echo "ERREUR: lancez ce script avec sudo." >&2; exit 1; }
    mkdir -p "$(dirname -- "$MARKER")"
    touch "$MARKER"
    chown jellyfin:jellyfin "$MARKER" 2>/dev/null || true
    systemctl restart jellyfin
    echo "Mode sûr JFIC activé: Harmony reste chargé, mais les hooks FFmpeg sont désactivés."
    ;;
  off)
    [[ $EUID -eq 0 ]] || { echo "ERREUR: lancez ce script avec sudo." >&2; exit 1; }
    rm -f -- "$MARKER"
    systemctl restart jellyfin
    echo "Mode sûr JFIC désactivé: hooks FFmpeg autorisés sur les transcodages vidéo existants."
    ;;
  status)
    if [[ -f "$MARKER" ]]; then echo "ON - hooks FFmpeg JFIC désactivés."; else echo "OFF - hooks FFmpeg JFIC autorisés."; fi
    ;;
  *)
    echo "Usage: sudo bash ffmpeg-safe-mode.sh {on|off|status}" >&2
    exit 2
    ;;
esac
