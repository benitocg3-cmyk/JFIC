# Backend NVIDIA / NVENC

## Cible

- Jellyfin Server : 10.11.11
- OS serveur : Ubuntu
- HWA Jellyfin : NVIDIA NVDEC/NVENC
- Mode plugin : **NVENC-only** pour tout filtre serveur JFIC
- FFmpeg : `jellyfin-ffmpeg7` / FFmpeg 7.1.x recommandé pour Jellyfin 10.11.x

## Règle

JFIC n'intervient côté FFmpeg que lorsque Jellyfin a **déjà choisi de réencoder la vidéo**.

Le garde-fou est appliqué à plusieurs niveaux :

1. le Web JFIC ne modifie jamais les capacités de lecture du client ;
2. le plugin refuse `EncodingHelper.IsCopyCodec(state.OutputVideoCodec)` ;
3. même le hook de chaîne logicielle exige un `vidEncoder` contenant `nvenc` (`h264_nvenc`, `hevc_nvenc` ou `av1_nvenc`) ;
4. le backend NVIDIA préféré exige également un encodeur `nvenc` ;
5. en cas d'erreur, le patch est ignoré et le traitement reste local.

## Pipeline NVIDIA natif de Jellyfin 10.11.11

Schéma simplifié :

```text
NVDEC/CUDA
   ↓
yadif_cuda / transpose_cuda / scale_cuda
   ↓
tonemap_cuda (si HDR→SDR)
   ↓
overlay_cuda (si nécessaire)
   ↓
NVENC
```

Selon les codecs, sous-titres et le décodage disponible, Jellyfin peut aussi avoir des frames en mémoire système avant NVENC.

## Pipeline JFIC

### Frame déjà en mémoire

```text
frame RAM
   ↓
eq + hue
   ↓
NVENC
```

### Frame CUDA

```text
frame CUDA
   ↓
hwdownload
   ↓
format=yuv420p
   ↓
eq + hue
   ↓
hwupload=derive_device=cuda
   ↓
overlay_cuda éventuel
   ↓
NVENC
```

Le copy-back reprend le format `yuv420p` que Jellyfin 10.11.11 utilise lui-même lors de ses sorties CUDA vers mémoire dans la chaîne NVIDIA.

## Filtres

JFIC utilise :

```text
eq=brightness=...:contrast=...:saturation=...:gamma=...
hue=h=...
```

La température de couleur n'est pas injectée dans FFmpeg.

## Coût attendu

L'encodage reste NVENC, mais le copy-back CUDA ajoute :

- un transfert VRAM → RAM ;
- le calcul de `eq`/`hue` côté CPU ;
- un transfert RAM → VRAM.

La charge dépend de la résolution et du nombre de flux simultanés. Il faut donc mesurer le débit de transcodage (`fps`) et l'utilisation CPU/GPU sur votre machine réelle.

## Préflight Ubuntu

```bash
sudo bash nvidia-preflight.sh --strict
```

Le script vérifie notamment :

```text
nvidia-smi
sudo -u jellyfin nvidia-smi -L
h264_nvenc
hevc_nvenc
av1_nvenc (si le GPU le supporte)
scale_cuda
hwupload_cuda
eq
hue
```

Il affiche également la version de `jellyfin-ffmpeg` détectée.

## Validation pendant une lecture

Dans le Dashboard Jellyfin, vérifier qu'un flux est déjà en transcodage vidéo et que l'encodeur est NVENC. Ensuite modifier un curseur JFIC et consulter :

```bash
sudo bash doctor.sh
```

Les logs JFIC doivent mentionner un backend `ffmpeg-nvenc` et indiquer si la surface était CUDA.

La commande FFmpeg générée doit conserver un encodeur du type :

```text
-codec:v h264_nvenc
-codec:v hevc_nvenc
-codec:v av1_nvenc   # GPU compatibles
```

et, pour une surface CUDA, contenir la séquence JFIC :

```text
hwdownload,format=yuv420p,eq=...,hue=...,hwupload=derive_device=cuda
```

## HDR

Le filtre JFIC est ajouté **après** les filtres déjà construits dans la liste principale NVIDIA. Si Jellyfin effectue un HDR→SDR avec `tonemap_cuda`, JFIC traite donc la sortie tonemappée plutôt que de modifier arbitrairement les valeurs HDR avant tone mapping.

La température reste locale pour éviter de modifier sans contrôle les primaires / le point blanc serveur.


## Mode sûr

Pour isoler immédiatement un problème FFmpeg sans désinstaller le Web ni le plugin :

```bash
sudo bash ffmpeg-safe-mode.sh on
```

Le script de mode sûr crée un marqueur JFIC puis redémarre Jellyfin. Harmony reste fourni, mais les deux hooks FFmpeg ne sont pas installés tant que le marqueur est présent. Le traitement client Web continue de fonctionner.

Pour réactiver :

```bash
sudo bash ffmpeg-safe-mode.sh off
```
