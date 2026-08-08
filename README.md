# Jellyfin Image Controls — 1.0.0-beta2
<img width="1044" height="1180" alt="JFIC" src="https://github.com/user-attachments/assets/b2cfa7b1-89d5-49b2-bccc-cd9028c335bb" />

JFIC cible Jellyfin Server 10.11.11 et NVIDIA NVENC/NVDEC.

Il y a deux cas distincts :

- Direct Play / Direct Stream : les réglages sont appliqués dans Firefox par CSS/SVG, après décodage. Aucun transcodage n'est demandé.
- Transcodage vidéo déjà choisi par Jellyfin : Harmony ajoute les filtres à la chaîne FFmpeg existante. JFIC ne transforme jamais une vidéo `copy` en transcodage.

## Installation simple par Bureau à distance

Copiez le ZIP sur Ubuntu dans `~/jfic-install`, puis ouvrez un terminal :

```bash
cd ~/jfic-install
python3 unzip -o JellyfinImageControls-Ubuntu-1.0.0-beta2.zip .
sudo bash install.sh
sudo bash doctor.sh
```

L'installation standard installe le plugin et un overlay Web appartenant à
JFIC. Elle ne modifie pas `/usr/share/jellyfin/web`, les binaires Jellyfin,
les médias ou `/etc/jellyfin`. Le petit drop-in
`/etc/systemd/system/jellyfin.service.d/90-jfic-web.conf` est créé par JFIC
pour servir sa copie Web ; `uninstall.sh` le supprime.

Si vous voulez uniquement le plugin serveur :

```bash
sudo bash install.sh --no-web
```

Dans ce mode, le backend Harmony fonctionne pour les transcodages existants,
mais aucun bouton ne peut apparaître automatiquement dans Jellyfin Web.

## Utilisation

Dans Firefox/Chrome/Android App, lancez une vidéo puis cliquez sur le bouton `palette`. Les
réglages sont locaux au navigateur et sont mémorisés. En Direct Stream, c'est
ce traitement local qui est utilisé. Pendant un transcodage vidéo existant,
le panneau indique si FFmpeg/NVENC a pris la main ; la température reste
locale.

## Désinstallation complète de JFIC

Depuis le même dossier :

```bash
sudo bash uninstall.sh
```

Cette commande retire le plugin, `0Harmony.dll`, l'overlay Web JFIC, son
drop-in et son état. Elle conserve Jellyfin officiel, son Web natif, ses
paramètres, sa base et les médias.

Pour supprimer aussi la configuration XML du plugin :

```bash
sudo bash uninstall.sh --purge-config
```

## Diagnostic

```bash
sudo bash doctor.sh
sudo bash verify-base.sh
```

Le journal attendu contient `JFIC Harmony runtime patch active`. Si Harmony
échoue, le plugin ne casse pas Jellyfin : le diagnostic indique l'erreur et
la lecture continue sans filtre serveur.

## Mode sûr temporaire

```bash
sudo bash ffmpeg-safe-mode.sh on
sudo bash ffmpeg-safe-mode.sh status
sudo bash ffmpeg-safe-mode.sh off
```

Ce mode désactive uniquement les hooks FFmpeg JFIC au redémarrage ; Harmony
reste fourni pour le fonctionnement normal.

## Développement Windows

```powershell
.\eng\Build.ps1
.\eng\Package-Ubuntu.ps1
```

Le ZIP est généré dans `dist\JellyfinImageControls-Ubuntu-1.0.0-beta2.zip`.
