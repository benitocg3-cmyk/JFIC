# Changelog

## 1.0.0-beta2

- Backend ciblé NVIDIA/NVENC pour Jellyfin 10.11.11.
- Patch runtime de `EncodingHelper.GetNvidiaVidFiltersPrefered` en plus de la chaîne logicielle.
- Garde-fou : backend NVIDIA actif uniquement si l'encodeur réel contient `nvenc`.
- Copy-back contrôlé CUDA → RAM → CUDA uniquement pendant un transcodage vidéo NVENC déjà actif.
- Réutilisation du format `yuv420p` cohérente avec le pipeline NVIDIA de Jellyfin 10.11.11.
- Température maintenue côté client.
- Ajout du préflight `nvidia-preflight.sh` et diagnostic NVIDIA étendu.
- Installation interrompue avant toute modification si le préflight NVIDIA strict échoue.
- Tests supplémentaires du builder NVENC et du suivi de surface CUDA.
- Les valeurs neutres / température seule ne créent plus un filtre FFmpeg inutile.
- Mode `NvencOnly` : même le hook de chaîne logicielle refuse tout encodeur autre que NVENC.
- Support de détection `av1_nvenc` dans le préflight pour les GPU compatibles.
- Safe mode FFmpeg/NVENC par fichier marqueur, activable localement ou depuis Windows.
- Rollback enrichi : restauration de l’état JFIC précédent, y compris le state-root.
- Déploiement Windows enrichi avec une action `Rollback` distante.
- Pont MPV protégé contre le double filtrage lorsque FFmpeg a confirmé la révision courante.

## 1.0.0-beta1

- Première architecture Windows → Ubuntu réversible.
- Web overlay, plugin serveur, patch logiciel FFmpeg, profils utilisateur/appareil.
- Installation, rollback, vérification et désinstallation sûrs.
