# Installation et désinstallation JFIC sur Ubuntu

Ce guide suppose que le ZIP a été copié par Bureau à distance dans
`~/jfic-install`.

## 1. Installer

```bash
cd ~/jfic-install
python3 -m zipfile -e JellyfinImageControls-Ubuntu-1.0.0-beta2.zip .
sudo bash install.sh
sudo bash doctor.sh
```

À quoi servent ces commandes :

- `cd` ouvre le dossier où se trouve le ZIP ;
- `python3 -m zipfile -e` extrait l'archive dans ce dossier ;
- `install.sh` vérifie la version Jellyfin/NVIDIA, installe le plugin et redémarre Jellyfin ;
- `doctor.sh` vérifie le plugin, Harmony, l'overlay Web et le service.

L'installation standard active aussi l'interface Firefox. JFIC copie le Web
officiel dans `/opt/jellyfin-image-controls/current/web`, y ajoute ses deux
assets, puis crée uniquement ce fichier JFIC-owned :

```text
/etc/systemd/system/jellyfin.service.d/90-jfic-web.conf
```

Le Web officiel `/usr/share/jellyfin/web` n'est jamais édité ni remplacé.

Pour installer sans interface Web :

```bash
sudo bash install.sh --no-web
```

Cette option respecte un mode strict « plugin serveur seulement », mais ne
peut évidemment pas afficher le bouton dans Firefox.

## 2. Vérifier que cela fonctionne

```bash
sudo bash verify-base.sh
sudo journalctl -u jellyfin -n 200 --no-pager | grep -Ei 'JFIC|Image Controls|Harmony'
```

Après redémarrage, la ligne importante est :

```text
JFIC Harmony runtime patch active
```

Dans Firefox, rechargez complètement la page (`Ctrl+F5`), démarrez une vidéo
et cliquez sur `☀ Image`.

Le comportement attendu est :

- Direct Play / Direct Stream : correction CSS/SVG locale dans Firefox ;
- vidéo déjà transcodée : filtre FFmpeg ajouté à cette session existante ;
- vidéo `copy` : aucun filtre FFmpeg et aucune conversion forcée.

## 3. Désinstaller clairement

```bash
cd ~/jfic-install
sudo bash uninstall.sh
```

Le script arrête Jellyfin quelques secondes, supprime uniquement :

- `/var/lib/jellyfin/plugins/Image Controls_1.0.0.0/` ;
- `/opt/jellyfin-image-controls/` ;
- `/etc/systemd/system/jellyfin.service.d/90-jfic-web.conf` ;
- `/var/lib/jellyfin-image-controls/`.

Il ne supprime pas Jellyfin, `/usr/share/jellyfin/web`, `/etc/jellyfin`, la
base de données ni les médias.

La configuration XML JFIC est conservée par défaut. Pour la supprimer :

```bash
sudo bash uninstall.sh --purge-config
```

## 4. Si Harmony échoue

Le lecteur continue sans filtre serveur, mais `doctor.sh` affichera l'erreur.
Ne supprimez pas une DLL Jellyfin à la main. Vérifiez d'abord :

```bash
sudo bash doctor.sh
sudo journalctl -u jellyfin -n 200 --no-pager | grep -Ei 'JFIC|Harmony|FileLoadException'
```

Le paquet JFIC fournit `0Harmony.dll` dans le dossier du plugin et utilise la
version Harmony sélectionnée pour Jellyfin 10.11.x.
