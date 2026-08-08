#!/usr/bin/env bash
set -Eeuo pipefail

cat <<'TEXT'
Le mode d'installation actuel de JFIC ne modifie pas Jellyfin et ne cree pas
de sauvegarde de configuration Jellyfin. Il n'y a donc pas de rollback a
restaurer : pour revenir a l'etat precedent, utilisez simplement:

  sudo bash uninstall.sh

Cette action retire le plugin et conserve Jellyfin Web, ses parametres et vos
donnees.
TEXT
