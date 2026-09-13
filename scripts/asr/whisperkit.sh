#!/usr/bin/env bash
# Host WhisperKit CLI (Core ML / ANE).
# usage: whisperkit.sh WAV OUT_DIR [model]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=/dev/null
source "$ROOT/scripts/asr/_common.sh"

WAV=${1:?wav}
OUT=${2:?out dir}
MODEL=${3:-small}
RUNTIME=whisperkit
mkdir -p "$OUT"

need whisperkit-cli

REPORT=$OUT/report
mkdir -p "$REPORT"
time_cmd whisperkit-cli transcribe \
  --model "$MODEL" \
  --audio-path "$WAV" \
  --word-timestamps \
  --report \
  --report-path "$REPORT" \
  --verbose

# stdout is the transcript; reports are srt/json under report-path
if [[ ! -s "$OUT/transcript.txt" ]]; then
  # CLI prints to stdout; time_cmd swallowed it. Recover from report json/srt.
  json=$(find "$REPORT" -name '*.json' | head -1 || true)
  srt=$(find "$REPORT" -name '*.srt' | head -1 || true)
  if [[ -n "$json" ]]; then
    python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('text','').strip())" "$json" >"$OUT/transcript.txt"
  fi
  if [[ -n "$srt" ]]; then
    cp "$srt" "$OUT/transcript.srt"
  fi
fi

if [[ ! -s "$OUT/transcript.txt" ]]; then
  fail_runtime "empty transcript (whisperkit)"
fi
[[ -f "$OUT/transcript.srt" ]] || : >"$OUT/transcript.srt"
write_asr_status ok
write_bench ok "${WALL:-0}" "${RSS_MB:-0}" ane
echo "whisperkit done wall=${WALL:-?}s rss=${RSS_MB:-?}MB"
