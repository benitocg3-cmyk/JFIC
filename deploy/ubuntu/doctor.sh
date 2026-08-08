#!/usr/bin/env bash
set -u

STATE_FILE="/var/lib/jellyfin-image-controls/install-state.env"
PLUGIN_ROOT="/var/lib/jellyfin/plugins"
PLUGIN_DIR="$PLUGIN_ROOT/Image Controls_1.0.0.0"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
rc=0

printf '=== Jellyfin Image Controls doctor ===\n'
printf 'Date: %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
jellyfin_version="$(jellyfin --version 2>/dev/null | head -n1 || true)"
if [[ -z "$jellyfin_version" ]]; then
  jellyfin_version="$(dpkg-query -W -f='${Version}' jellyfin-server 2>/dev/null || true)"
fi
printf 'Jellyfin version: %s\n' "${jellyfin_version:-inconnu}"
printf 'Service: %s\n' "$(systemctl is-active jellyfin 2>/dev/null || true)"
printf 'JFIC state: %s\n' "$(test -f "$STATE_FILE" && echo present || echo absent)"
printf 'JFIC plugin: %s\n' "$(test -f "$PLUGIN_DIR/Jellyfin.Plugin.ImageControls.dll" && echo present || echo absent)"
if [[ -f "$PLUGIN_DIR/0Harmony.dll" ]]; then
  printf 'Harmony: present (%s)\n' "$(stat -c '%a %U:%G' "$PLUGIN_DIR/0Harmony.dll" 2>/dev/null || true)"
else
  printf 'Harmony: MISSING\n'
  rc=1
fi
if [[ -f /opt/jellyfin-image-controls/current/web/index.html ]]; then
  if grep -q 'data-jfic="1"' /opt/jellyfin-image-controls/current/web/index.html 2>/dev/null \
    && [[ -f /opt/jellyfin-image-controls/current/web/image-controls.js ]] \
    && [[ -f /opt/jellyfin-image-controls/current/web/image-controls.css ]]; then
    printf 'JFIC Web overlay: present (assets injectes)\n'
  else
    printf 'JFIC Web overlay: PRESENT MAIS NON INJECTE\n'
    rc=1
  fi
else
  printf 'JFIC Web overlay: absent (server plugin only)\n'
fi
printf 'Official Jellyfin Web: %s\n' "$(test -f /usr/share/jellyfin/web/index.html && echo present || echo absent)"
printf 'JFIC systemd drop-in: %s\n' "$(test -e /etc/systemd/system/jellyfin.service.d/90-jfic-web.conf && echo ATTENTION-present || echo absent)"

printf 'Effective Web environment:\n'
systemctl show jellyfin -p Environment --value 2>/dev/null \
  | tr ' ' '\n' | grep -E '^JELLYFIN_WEB_(OPT|DIR)=' | sed 's/^/  /' || true
printf 'Effective ExecStart:\n'
systemctl show jellyfin -p ExecStart --value 2>/dev/null \
  | grep -oE -- '--webdir=[^ ]+' | sed 's/^/  /' || true

printf 'HTTP Web served locally:\n'
if command -v curl >/dev/null 2>&1; then
  served_index="$(curl -fsSL --max-time 5 http://127.0.0.1:8096/ 2>/dev/null || true)"
  if grep -q 'data-jfic="1"' <<<"$served_index"; then
    printf '  JFIC overlay served (index contains data-jfic)\n'
  elif [[ -n "$served_index" ]]; then
    printf '  ATTENTION: HTTP répond, mais index JFIC absent\n'
    rc=1
  else
    printf '  Indéterminé (HTTP 8096 inaccessible ou base URL différente)\n'
  fi
else
  printf '  curl indisponible\n'
fi

printf '\nNVIDIA/NVENC:\n'
if [[ -x "$SCRIPT_DIR/nvidia-preflight.sh" ]]; then
  "$SCRIPT_DIR/nvidia-preflight.sh" || true
else
  command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || echo 'nvidia-smi indisponible'
fi

printf '\nRecent JFIC logs:\n'
journalctl -u jellyfin -n 120 --no-pager 2>/dev/null | grep -Ei 'JFIC|Image Controls|ImageControls' | tail -n 40 || true

printf '\nJFIC FFmpeg safe mode:\n'
if [[ -f /var/lib/jellyfin-image-controls/disable-ffmpeg-patch ]]; then
  echo 'ON  - patch runtime FFmpeg/NVENC desactive; traitement client uniquement.'
else
  echo 'OFF - patch runtime FFmpeg/NVENC autorise.'
fi

if ! systemctl is-active --quiet jellyfin 2>/dev/null; then rc=1; fi
if [[ ! -f "$PLUGIN_DIR/Jellyfin.Plugin.ImageControls.dll" ]]; then rc=1; fi
exit "$rc"
