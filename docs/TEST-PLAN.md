# Plan de validation JFIC

## Build Windows

1. `eng\Package-Ubuntu.ps1` termine sans erreur.
2. Les 10 tests xUnit et le smoke-test Web passent.
3. Le ZIP contient `plugin/Jellyfin.Plugin.ImageControls.dll` et `plugin/0Harmony.dll`.
4. Les entrées ZIP utilisent `/` et non `\`.

## Installation Ubuntu

1. Copier le ZIP par Bureau à distance.
2. Extraire dans `~/jfic-install`.
3. Exécuter `sudo bash install.sh` puis `sudo bash doctor.sh`.
4. Vérifier `JFIC Harmony runtime patch active` dans le journal.
5. Vérifier la présence de `/opt/jellyfin-image-controls/current/web/index.html`.
6. Tester Firefox en Direct Stream et pendant un transcodage vidéo réel.

## Invariants

- Direct Stream reste Direct Stream et reçoit uniquement le filtre local Web.
- Une vidéo `copy` ne reçoit jamais `eq`/`hue` côté FFmpeg.
- Un transcodage vidéo déjà actif peut recevoir le filtre JFIC.
- `/usr/share/jellyfin/web` et les binaires Jellyfin restent inchangés.

## Désinstallation

1. Exécuter `sudo bash uninstall.sh`.
2. Vérifier que le drop-in JFIC et `/opt/jellyfin-image-controls` ont disparu.
3. Vérifier que `/usr/share/jellyfin/web` et `/etc/jellyfin` sont toujours présents.
4. Vérifier que Jellyfin redémarre sans JFIC.
