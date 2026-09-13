#!/usr/bin/env bash
# Host whisper.cpp (brew whisper-cli, Metal on by default).
# usage: whisper_cpp.sh WAV OUT_DIR [ggml-model-filename]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=/dev/null
source "$ROOT/scripts/asr/_common.sh"

WAV=${1:?wav}
OUT=${2:?out dir}
MODEL=${3:-ggml-small.en.bin}
RUNTIME=whisper_cpp
MODELS=$ROOT/models
mkdir -p "$OUT" "$MODELS"

need whisper-cli

MODEL_PATH=$MODEL
if [[ "$MODEL" != /* ]]; then
  MODEL_PATH=$MODELS/$MODEL
fi
if [[ ! -f "$MODEL_PATH" ]]; then
  echo "downloading $MODEL"
  curl -fL --retry 3 "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$(basename "$MODEL_PATH")" \
    -o "$MODEL_PATH"
fi

PROMPT_TEXT=
if [[ -n "${GHOST_WHISPER_PROMPT:-}" ]]; then
  if [[ -f "$GHOST_WHISPER_PROMPT" ]]; then
    PROMPT_TEXT=$(cat "$GHOST_WHISPER_PROMPT")
  else
    PROMPT_TEXT=$GHOST_WHISPER_PROMPT
  fi
elif [[ -n "${GHOST_LEXICON:-}" ]]; then
  lex=$ROOT/lexicons/${GHOST_LEXICON}.txt
  [[ -f "$lex" ]] || fail_runtime "no lexicon file $lex"
  PROMPT_TEXT=$(cat "$lex")
fi
PROMPT_ARGS=()
if [[ -n "$PROMPT_TEXT" ]]; then
  PROMPT_ARGS=(--prompt "$PROMPT_TEXT")
  echo "whisper_cpp prompt: ${PROMPT_TEXT:0:80}"
fi

LANG=${GHOST_WHISPER_LANG:-en}
TASK=${GHOST_WHISPER_TASK:-transcribe}
EXTRA_ARGS=(-l "$LANG")
if [[ "$TASK" == "translate" ]]; then
  EXTRA_ARGS+=(-tr)
fi

PREFIX=$OUT/whisper
if [[ ${#PROMPT_ARGS[@]} -gt 0 ]]; then
  time_cmd whisper-cli -m "$MODEL_PATH" -f "$WAV" -otxt -osrt -oj -of "$PREFIX" -np \
    "${EXTRA_ARGS[@]}" "${PROMPT_ARGS[@]}"
else
  time_cmd whisper-cli -m "$MODEL_PATH" -f "$WAV" -otxt -osrt -oj -of "$PREFIX" -np \
    "${EXTRA_ARGS[@]}"
fi

if [[ -f ${PREFIX}.txt ]]; then mv -f "${PREFIX}.txt" "$OUT/transcript.txt"; fi
if [[ -f ${PREFIX}.srt ]]; then mv -f "${PREFIX}.srt" "$OUT/transcript.srt"; fi
if [[ -f ${PREFIX}.json ]]; then mv -f "${PREFIX}.json" "$OUT/whisper.json"; fi

if [[ ! -s "$OUT/transcript.txt" ]]; then
  fail_runtime "empty transcript"
fi
write_asr_status ok
write_bench ok "${WALL:-0}" "${RSS_MB:-0}" metal
echo "whisper_cpp done wall=${WALL:-?}s rss=${RSS_MB:-?}MB"
