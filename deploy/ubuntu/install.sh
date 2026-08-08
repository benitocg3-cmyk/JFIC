#!/usr/bin/env bash
set -Eeuo pipefail

JFIC_VERSION="1.0.0-beta2"
PLUGIN_ABI_VERSION="1.0.0.0"
PACKAGE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_BUNDLE="$PACKAGE_DIR/plugin"
PLUGIN_ROOT="/var/lib/jellyfin/plugins"
PLUGIN_DIR="$PLUGIN_ROOT/Image Controls_$PLUGIN_ABI_VERSION"
STATE_ROOT="/var/lib/jellyfin-image-controls"
STATE_FILE="$STATE_ROOT/install-state.env"
LEGACY_OPT_ROOT="/opt/jellyfin-image-controls"
LEGACY_DROPIN="/etc/systemd/system/jellyfin.service.d/90-jfic-web.conf"
WEB_ROOT="/opt/jellyfin-image-controls"
WEB_CURRENT="$WEB_ROOT/current/web"
WEB_SOURCE="/usr/share/jellyfin/web"
FORCE_VERSION=0
NO_RESTART=0
WITH_WEB=1

usage() {
  cat <<'USAGE'
Usage: sudo bash install.sh [--no-web] [--force-version] [--no-restart]

Installe le plugin JFIC et, par defaut, une copie JFIC-owned de Jellyfin Web.
La copie native /usr/share/jellyfin/web n'est jamais modifiee. Le seul override
est /etc/systemd/system/jellyfin.service.d/90-jfic-web.conf, supprime par
uninstall.sh. --no-web installe uniquement le plugin serveur.
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --force-version) FORCE_VERSION=1 ;;
    --no-restart) NO_RESTART=1 ;;
    --no-web) WITH_WEB=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Option inconnue: $arg" >&2; usage; exit 2 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "ERREUR: lancez ce script avec sudo." >&2; exit 1; }
command -v systemctl >/dev/null || { echo "ERREUR: systemd est requis pour redemarrer Jellyfin." >&2; exit 1; }
[[ -f "$PLUGIN_BUNDLE/Jellyfin.Plugin.ImageControls.dll" ]] || {
  echo "ERREUR: plugin compile absent: $PLUGIN_BUNDLE/Jellyfin.Plugin.ImageControls.dll" >&2
  exit 1
}
[[ -f "$PLUGIN_BUNDLE/0Harmony.dll" ]] || {
  echo "ERREUR: 0Harmony.dll absente du paquet." >&2
  exit 1
}
if [[ $WITH_WEB -eq 1 ]]; then
  [[ -f "$WEB_SOURCE/index.html" ]] || {
    echo "ERREUR: Jellyfin Web introuvable: $WEB_SOURCE" >&2
    exit 1
  }
  command -v python3 >/dev/null || {
    echo "ERREUR: python3 est requis pour injecter le Web JFIC." >&2
    exit 1
  }
fi

get_version() {
  local v=""
  if command -v jellyfin >/dev/null 2>&1; then
    v="$(jellyfin --version 2>/dev/null | head -n1 || true)"
  fi
  if [[ -z "$v" ]] && command -v dpkg-query >/dev/null 2>&1; then
    v="$(dpkg-query -W -f='${Version}' jellyfin-server 2>/dev/null || true)"
  fi
  printf '%s' "$v"
}

JELLYFIN_VERSION="$(get_version)"
if [[ $FORCE_VERSION -ne 1 && ! "$JELLYFIN_VERSION" =~ 10\.11\.11 ]]; then
  echo "ERREUR: ce plugin cible Jellyfin 10.11.11; detecte: ${JELLYFIN_VERSION:-inconnu}" >&2
  echo "Utilisez --force-version uniquement si vous avez valide la compatibilite." >&2
  exit 1
fi

if [[ -x "$PACKAGE_DIR/nvidia-preflight.sh" ]]; then
  echo "Verification NVIDIA/NVENC..."
  "$PACKAGE_DIR/nvidia-preflight.sh" --strict
fi

WAS_ACTIVE=0
if systemctl is-active --quiet jellyfin; then WAS_ACTIVE=1; fi

mkdir -p "$STATE_ROOT" "$PLUGIN_ROOT"
# Jellyfin must be able to enter the JFIC-owned state directory to let
# This directory is JFIC-owned state, not Jellyfin configuration.
chown jellyfin:jellyfin "$STATE_ROOT" 2>/dev/null || true
chmod 750 "$STATE_ROOT"

echo "[1/3] Arret temporaire de Jellyfin..."
if [[ $WAS_ACTIVE -eq 1 ]]; then systemctl stop jellyfin; fi

echo "[2/4] Installation du plugin dans: $PLUGIN_DIR"
rm -rf "$PLUGIN_DIR"
mkdir -p "$PLUGIN_DIR"
cp -a "$PLUGIN_BUNDLE/." "$PLUGIN_DIR/"
chown -R jellyfin:jellyfin "$PLUGIN_DIR" 2>/dev/null || true

if [[ $WITH_WEB -eq 1 ]]; then
  echo "[3/4] Installation du Web JFIC dans: $WEB_CURRENT"
  rm -rf "$WEB_ROOT/current"
  mkdir -p "$WEB_CURRENT"
  cp -a "$WEB_SOURCE/." "$WEB_CURRENT/"
  cp -f "$PACKAGE_DIR/web/image-controls.js" "$WEB_CURRENT/image-controls.js"
  cp -f "$PACKAGE_DIR/web/image-controls.css" "$WEB_CURRENT/image-controls.css"
  python3 - "$WEB_CURRENT/index.html" <<'PY_INJECT'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
if 'data-jfic="1"' not in text:
    marker = '<link rel="stylesheet" href="image-controls.css?v=1.0.0-beta2.9" data-jfic="1">\n<script src="image-controls.js?v=1.0.0-beta2.9" data-jfic="1"></script>\n'
    if '<head>' not in text:
        raise SystemExit('Balise <head> absente dans Jellyfin Web')
    text = text.replace('<head>', '<head>\n' + marker, 1)
    path.write_text(text, encoding='utf-8')
PY_INJECT
  grep -q 'data-jfic="1"' "$WEB_CURRENT/index.html" || {
    echo "ERREUR: l'overlay JFIC n'a pas pu être injecté dans Jellyfin Web." >&2
    exit 1
  }
  mkdir -p "$(dirname -- "$LEGACY_DROPIN")"
  cat > "$LEGACY_DROPIN" <<EOF_DROPIN
[Service]
Environment="JELLYFIN_WEB_OPT=--webdir=$WEB_CURRENT"
Environment="JELLYFIN_WEB_DIR=$WEB_CURRENT"
ExecStart=
ExecStart=/usr/bin/jellyfin --webdir=$WEB_CURRENT \$JELLYFIN_FFMPEG_OPT \$JELLYFIN_SERVICE_OPT \$JELLYFIN_NOWEBAPP_OPT \$JELLYFIN_ADDITIONAL_OPTS
EOF_DROPIN
  chown -R jellyfin:jellyfin "$WEB_ROOT" 2>/dev/null || true
else
  rm -f -- "$LEGACY_DROPIN"
  rm -rf -- "$LEGACY_OPT_ROOT"
fi

systemctl daemon-reload

cat > "$STATE_FILE" <<STATE
JFIC_VERSION='$JFIC_VERSION'
TARGET_JELLYFIN='10.11.11'
PLUGIN_DIR='$PLUGIN_DIR'
INSTALL_MODE='$([[ $WITH_WEB -eq 1 ]] && echo plugin+web-overlay || echo plugin-only)'
STATE
chmod 600 "$STATE_FILE"

if [[ $NO_RESTART -eq 1 ]]; then
  echo "[4/4] Installation terminee. Jellyfin n'a pas ete redemarre (--no-restart)."
  echo "Redemarrez-le avant d'utiliser le plugin: sudo systemctl restart jellyfin"
  exit 0
fi

echo "[4/4] Redemarrage de Jellyfin..."
if [[ $WAS_ACTIVE -eq 1 ]]; then
  systemctl start jellyfin
  for _ in $(seq 1 20); do
    systemctl is-active --quiet jellyfin && break
    sleep 1
  done
  systemctl is-active --quiet jellyfin || {
    echo "ERREUR: Jellyfin n'a pas redemarre. Le plugin reste dans $PLUGIN_DIR." >&2
    exit 1
  }
else
  echo "Jellyfin etait deja arrete: il reste arrete."
fi

echo "Installation JFIC terminee."
echo "Plugin: $PLUGIN_DIR"
if [[ $WITH_WEB -eq 1 ]]; then echo "Web Firefox: actif via un overlay JFIC reversible."; else echo "Web Firefox: non installe (--no-web)."; fi
echo "Desinstallation: sudo bash $PACKAGE_DIR/uninstall.sh"
echo "Diagnostic: sudo bash $PACKAGE_DIR/doctor.sh"
