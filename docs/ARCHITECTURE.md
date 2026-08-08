# Architecture JFIC 1.0.0-beta2

## Deux backends, deux responsabilités

Le navigateur et FFmpeg ne travaillent pas au même moment :

```text
Direct Stream / Direct Play ──> vidéo décodée par Firefox ──> CSS/SVG JFIC
Transcodage vidéo existant ──> EncodingHelper Jellyfin ──Harmony──> FFmpeg
```

JFIC n'ajoute jamais de transcodage pour obtenir des réglages d'image.

## Plugin et Harmony

Le plugin est installé dans :

```text
/var/lib/jellyfin/plugins/Image Controls_1.0.0.0/
```

`0Harmony.dll` est livré dans ce dossier. Au démarrage, le plugin cible les
méthodes `EncodingHelper.GetSwVidFilterChain` et
`EncodingHelper.GetNvidiaVidFiltersPrefered` de Jellyfin 10.11.11. Les postfixes
refusent `OutputVideoCodec=copy`, refusent les encodeurs non-NVENC en mode
NVENC-only et n'ajoutent un filtre qu'à une vidéo déjà en transcodage.

Jellyfin et ses DLL ne sont pas remplacés sur disque.

## Direct Stream

Le Web JFIC est une copie dans `/opt/jellyfin-image-controls/current/web`.
L'overlay ajoute `image-controls.js` et `image-controls.css` à `index.html`.
Le fichier natif `/usr/share/jellyfin/web` reste intact. Le routage vers la
copie est assuré par un drop-in JFIC-owned et est retiré par la désinstallation.

Le filtre CSS/SVG est post-décodage : il ne modifie pas les capacités de
lecture et ne force pas de transcodage.

## NVIDIA

Quand une session NVENC existe déjà, JFIC conserve NVENC. Si Jellyfin fournit
une surface CUDA, le backend peut effectuer un copy-back contrôlé
(`hwdownload`, `eq`/`hue`, `hwupload` CUDA), puis laisser NVENC encoder.
La température reste côté client.
