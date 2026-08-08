#!/usr/bin/env bash
set -Eeuo pipefail

PLUGIN_ROOT="/var/lib/jellyfin/plugins"
STATE_ROOT="/var/lib/jellyfin-image-controls"
STATE_FILE="$STATE_ROOT/install-state.env"
LEGACY_OPT_ROOT="/opt/jellyfin-image-controls"
LEGACY_DROPIN="/etc/systemd/system/jellyfin.service.d/90-jfic-web.conf"
BACKUP_ROOT="/var/backups/jellyfin-image-controls"
PURGE_CONFIG=0
PURGE_BACKUPS=0

usage() {
  echo "Usage: sudo bash uninstall.sh [--purge-config] [--purge-backups]"
}

for arg in "$@"; do
  case "$arg" in
    --purge-config) PURGE_CONFIG=1 ;;
    --purge-backups) PURGE_BACKUPS=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Option inconnue: $arg" >&2; usage; exit 2 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "ERREUR: lancez ce script avec sudo." >&2; exit 1; }
command -v systemctl >/dev/null || { echo "ERREUR: systemd est requis." >&2; exit 1; }

WAS_ACTIVE=0
if systemctl is-active --quiet jellyfin; then WAS_ACTIVE=1; fi

echo "Ce script supprime uniquement JFIC."
echo "Il ne supprime ni /usr/bin/jellyfin, ni /usr/share/jellyfin/web, ni /etc/jellyfin, ni vos medias."
echo "Arret temporaire de Jellyfin..."
if [[ $WAS_ACTIVE -eq 1 ]]; then systemctl stop jellyfin; fi

echo "Suppression du plugin Image Controls..."
find "$PLUGIN_ROOT" -maxdepth 1 -mindepth 1 -type d -name 'Image Controls_*' -exec rm -rf -- {} + 2>/dev/null || true
if [[ $PURGE_CONFIG -eq 1 && -d "$PLUGIN_ROOT/configurations" ]]; then
  find "$PLUGIN_ROOT/configurations" -maxdepth 1 -type f \
    \( -iname '*Image Controls*.xml' -o -iname '*ImageControls*.xml' \) -delete 2>/dev/null || true
  echo "Configuration JFIC supprimee (--purge-config)."
fi

rm -rf -- "$STATE_ROOT"

# Nettoyage de l'installation beta precedente. Ces chemins appartenaient a
# JFIC; aucun fichier natif Jellyfin n'est supprime.
rm -rf -- "$LEGACY_OPT_ROOT"
rm -f -- "$LEGACY_DROPIN"
if [[ -d /etc/systemd/system/jellyfin.service.d ]] && \
   [[ -z "$(find /etc/systemd/system/jellyfin.service.d -mindepth 1 -maxdepth 1 -type f -print -quit 2>/dev/null)" ]]; then
  rmdir /etc/systemd/system/jellyfin.service.d 2>/dev/null || true
fi
systemctl daemon-reload

if [[ $WAS_ACTIVE -eq 1 ]]; then
  systemctl start jellyfin
  for _ in $(seq 1 20); do
    systemctl is-active --quiet jellyfin && break
    sleep 1
  done
  systemctl is-active --quiet jellyfin || {
    echo "ERREUR: Jellyfin ne redemarre pas. Les fichiers natifs n'ont pas ete supprimes." >&2
    exit 1
  }
else
  echo "Jellyfin etait deja arrete: il reste arrete."
fi

if [[ $PURGE_BACKUPS -eq 1 ]]; then
  rm -rf -- "$BACKUP_ROOT"
  echo "Anciennes sauvegardes JFIC supprimees (--purge-backups)."
else
  echo "Anciennes sauvegardes conservees dans: $BACKUP_ROOT"
fi

echo "JFIC desinstalle. Jellyfin natif est conserve."
