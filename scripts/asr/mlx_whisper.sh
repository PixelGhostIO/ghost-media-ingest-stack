#!/usr/bin/env bash
# Host mlx-whisper (Apple MLX / Metal).
# usage: mlx_whisper.sh WAV OUT_DIR [hf-model-id]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=/dev/null
source "$ROOT/scripts/asr/_common.sh"

WAV=${1:?wav}
OUT=${2:?out dir}
MODEL=${3:-mlx-community/whisper-small.en-mlx}
RUNTIME=mlx_whisper
mkdir -p "$OUT"

# Prefer the 3.12 mlx venv; Homebrew python3 is 3.14 and tiktoken SIGSEGVs.
if [[ -x $ROOT/.venv-mlx/bin/mlx_whisper ]]; then
  VENV=$ROOT/.venv-mlx
  export PATH="$VENV/bin:$PATH"
fi

if [[ ! -x "$VENV/bin/mlx_whisper" ]]; then
  fail_runtime "mlx_whisper not in $VENV — run scripts/bootstrap-mac.sh mlx"
fi

STEM=$(basename "$WAV")
STEM=${STEM%.*}
LANG=${GHOST_WHISPER_LANG:-en}
TASK=${GHOST_WHISPER_TASK:-transcribe}
if [[ "$LANG" == "auto" || "$LANG" == "none" ]]; then
  time_cmd "$VENV/bin/mlx_whisper" "$WAV" \
    --model "$MODEL" \
    --task "$TASK" \
    -f all \
    -o "$OUT" \
    --output-name transcript
else
  time_cmd "$VENV/bin/mlx_whisper" "$WAV" \
    --model "$MODEL" \
    --task "$TASK" \
    --language "$LANG" \
    -f all \
    -o "$OUT" \
    --output-name transcript
fi

# mlx_whisper names files from --output-name
if [[ -f $OUT/transcript.txt ]]; then :; elif [[ -f $OUT/${STEM}.txt ]]; then
  mv -f "$OUT/${STEM}.txt" "$OUT/transcript.txt"
fi
if [[ -f $OUT/transcript.srt ]]; then :; elif [[ -f $OUT/${STEM}.srt ]]; then
  mv -f "$OUT/${STEM}.srt" "$OUT/transcript.srt"
fi

if [[ ! -s "$OUT/transcript.txt" ]]; then
  fail_runtime "empty transcript"
fi
write_asr_status ok
write_bench ok "${WALL:-0}" "${RSS_MB:-0}" mlx
echo "mlx_whisper done wall=${WALL:-?}s rss=${RSS_MB:-?}MB"
