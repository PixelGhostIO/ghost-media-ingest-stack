#!/usr/bin/env bash
# Host faster-whisper (CTranslate2, CPU int8 on Mac).
# usage: faster_whisper.sh WAV OUT_DIR [model]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=/dev/null
source "$ROOT/scripts/asr/_common.sh"

WAV=${1:?wav}
OUT=${2:?out dir}
MODEL=${3:-small.en}
RUNTIME=faster_whisper
mkdir -p "$OUT"

if [[ ! -x $VENV/bin/python ]]; then
  fail_runtime "venv missing — run scripts/bootstrap-mac.sh faster"
fi
"$VENV/bin/python" -c "import faster_whisper" 2>/dev/null \
  || fail_runtime "faster_whisper not installed — run scripts/bootstrap-mac.sh faster"

time_cmd "$VENV/bin/python" - "$WAV" "$OUT" "$MODEL" <<'PY'
import sys
from faster_whisper import WhisperModel

wav, out, model_name = sys.argv[1], sys.argv[2], sys.argv[3]

def ts(s: float) -> str:
    h, rem = divmod(int(s), 3600)
    m, sec = divmod(rem, 60)
    ms = int(round((s - int(s)) * 1000))
    return f"{h:02d}:{m:02d}:{sec:02d},{ms:03d}"

model = WhisperModel(model_name, device="cpu", compute_type="int8")
segments, _info = model.transcribe(wav, word_timestamps=True, beam_size=5)
lines = []
srt = []
for i, seg in enumerate(segments, 1):
    line = seg.text.strip()
    lines.append(line)
    srt.append(f"{i}\n{ts(seg.start)} --> {ts(seg.end)}\n{line}\n")
open(f"{out}/transcript.txt", "w", encoding="utf-8").write("\n".join(lines) + "\n")
open(f"{out}/transcript.srt", "w", encoding="utf-8").write("\n".join(srt) + "\n")
PY

if [[ ! -s "$OUT/transcript.txt" ]]; then
  fail_runtime "empty transcript"
fi
write_asr_status ok
write_bench ok "${WALL:-0}" "${RSS_MB:-0}" cpu
echo "faster_whisper done wall=${WALL:-?}s rss=${RSS_MB:-?}MB"
