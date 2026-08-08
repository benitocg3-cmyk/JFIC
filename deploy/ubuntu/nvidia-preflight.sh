#!/usr/bin/env bash
set -u

STRICT=0
[[ "${1:-}" == "--strict" ]] && STRICT=1
rc=0

find_ffmpeg() {
  local candidates=(
    /usr/lib/jellyfin-ffmpeg/ffmpeg
    /usr/lib/jellyfin-ffmpeg7/ffmpeg
    /usr/bin/ffmpeg
  )
  for f in "${candidates[@]}"; do
    [[ -x "$f" ]] && { printf '%s' "$f"; return 0; }
  done
  command -v ffmpeg 2>/dev/null || true
}

require_line() {
  local ok="$1" good="$2" bad="$3"
  if [[ "$ok" == "1" ]]; then printf 'OK   %s\n' "$good"; else printf 'WARN %s\n' "$bad"; rc=1; fi
}

info_line() {
  local ok="$1" good="$2" bad="$3"
  if [[ "$ok" == "1" ]]; then printf 'OK   %s\n' "$good"; else printf 'INFO %s\n' "$bad"; fi
}

printf '=== JFIC NVIDIA/NVENC preflight ===\n'
printf 'Date: %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"

if command -v nvidia-smi >/dev/null 2>&1; then
  printf '\nGPU / driver:\n'
  gpu_info="$(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || true)"
  if [[ -n "$gpu_info" ]]; then
    printf '%s\n' "$gpu_info"
    driver_version="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 | tr -d '[:space:]')"
    min_driver='520.56.06'
    if [[ -n "$driver_version" && "$(printf '%s\n%s\n' "$min_driver" "$driver_version" | sort -V | head -n1)" == "$min_driver" ]]; then
      echo "OK   driver NVIDIA $driver_version >= minimum Jellyfin 10.11 Linux $min_driver."
    else
      echo "WARN driver NVIDIA ${driver_version:-inconnu} inférieur/non comparable au minimum $min_driver."
      rc=1
    fi
  else
    echo 'WARN nvidia-smi présent mais inutilisable.'
    rc=1
  fi
else
  echo 'WARN nvidia-smi absent.'
  rc=1
fi

if id jellyfin >/dev/null 2>&1 && command -v nvidia-smi >/dev/null 2>&1; then
  if sudo -u jellyfin nvidia-smi -L >/dev/null 2>&1; then
    echo 'OK   utilisateur jellyfin voit le GPU NVIDIA.'
  else
    echo 'WARN utilisateur jellyfin ne peut pas interroger le GPU NVIDIA.'
    rc=1
  fi
fi

FFMPEG="$(find_ffmpeg)"
printf '\nFFmpeg Jellyfin: %s\n' "${FFMPEG:-introuvable}"
if [[ -z "$FFMPEG" ]]; then
  rc=1
else
  "$FFMPEG" -hide_banner -version 2>/dev/null | head -n 2 || true
  encoders="$($FFMPEG -hide_banner -encoders 2>/dev/null || true)"
  filters="$($FFMPEG -hide_banner -filters 2>/dev/null || true)"
  has_h264=$([[ "$encoders" == *h264_nvenc* ]] && echo 1 || echo 0)
  has_hevc=$([[ "$encoders" == *hevc_nvenc* ]] && echo 1 || echo 0)
  has_av1=$([[ "$encoders" == *av1_nvenc* ]] && echo 1 || echo 0)
  has_any_nvenc=$([[ "$has_h264" == 1 || "$has_hevc" == 1 || "$has_av1" == 1 ]] && echo 1 || echo 0)
  require_line "$has_any_nvenc" 'au moins un encodeur NVENC (H.264/HEVC/AV1) est disponible.' 'aucun encodeur h264_nvenc/hevc_nvenc/av1_nvenc détecté.'
  info_line "$has_h264" 'h264_nvenc disponible.' 'h264_nvenc absent (acceptable si vos profils ne l’utilisent pas).'
  info_line "$has_hevc" 'hevc_nvenc disponible.' 'hevc_nvenc absent (acceptable si vos profils ne l’utilisent pas).'
  info_line "$has_av1" 'av1_nvenc disponible.' 'av1_nvenc absent (normal sur les GPU sans encodeur AV1).'

  # Ces filtres CUDA permettent le chemin NVIDIA préféré de Jellyfin. Leur absence
  # ne doit pas rendre l'installation dangereuse : Jellyfin peut utiliser son
  # chemin copy-back logiciel, que JFIC sait également patcher.
  info_line "$([[ "$filters" == *scale_cuda* ]] && echo 1 || echo 0)" 'scale_cuda disponible.' 'scale_cuda absent; Jellyfin pourra utiliser son fallback copy-back.'
  info_line "$([[ "$filters" == *hwupload_cuda* ]] && echo 1 || echo 0)" 'hwupload_cuda disponible.' 'hwupload_cuda absent; le backend CUDA JFIC sera limité au fallback Jellyfin.'
  require_line "$([[ "$filters" == *" eq "* || "$filters" == *$'\neq '* ]] && echo 1 || echo 0)" 'filtre logiciel eq disponible.' 'filtre eq absent; JFIC ne peut pas appliquer luminosité/contraste/saturation/gamma côté FFmpeg.'
  require_line "$([[ "$filters" == *" hue "* || "$filters" == *$'\nhue '* ]] && echo 1 || echo 0)" 'filtre logiciel hue disponible.' 'filtre hue absent; JFIC ne peut pas garantir le backend FFmpeg complet.'

  if [[ "$filters" == *tonemap_cuda* ]]; then
    echo 'OK   tonemap_cuda disponible (utile pour HDR->SDR NVIDIA).'
  else
    echo 'INFO tonemap_cuda non détecté; cela ne bloque pas les vidéos SDR.'
  fi
fi

cat <<'INFO'

Mode JFIC NVENC:
  Direct Play / vidéo copy      : aucun FFmpeg ajouté
  Transcodage NVENC déjà actif  : eq/hue dans la chaîne existante
  Surface CUDA                  : hwdownload -> yuv420p -> eq/hue -> hwupload CUDA -> NVENC
  Température                   : reste côté client

Le copy-back peut augmenter l'usage CPU et PCIe, mais il ne remplace pas NVENC et ne déclenche jamais à lui seul un transcodage vidéo.
INFO

if [[ $STRICT -eq 1 ]]; then exit "$rc"; fi
exit 0
