#!/usr/bin/env bash
# Host lightning-whisper-mlx (abandoned 2024; MLX batched).
# usage: lightning_mlx.sh WAV OUT_DIR [model]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=/dev/null
source "$ROOT/scripts/asr/_common.sh"

WAV=${1:?wav}
OUT=${2:?out dir}
MODEL=${3:-small}
RUNTIME=lightning_mlx
mkdir -p "$OUT"

"$VENV/bin/python" -c "from lightning_whisper_mlx import LightningWhisperMLX" 2>/dev/null \
  || fail_runtime "lightning-whisper-mlx not installed — run scripts/bootstrap-mac.sh lightning"

set +e
time_cmd "$VENV/bin/python" - "$WAV" "$OUT" "$MODEL" <<'PY'
import sys
from lightning_whisper_mlx import LightningWhisperMLX

wav, out, model_name = sys.argv[1], sys.argv[2], sys.argv[3]

def ts(s: float) -> str:
    h, rem = divmod(int(s), 3600)
    m, sec = divmod(rem, 60)
    ms = int(round((s - int(s)) * 1000))
    return f"{h:02d}:{m:02d}:{sec:02d},{ms:03d}"

w = LightningWhisperMLX(model=model_name, batch_size=12)
result = w.transcribe(audio_path=wav)
text = (result.get("text") or "").strip()
open(f"{out}/transcript.txt", "w", encoding="utf-8").write(text + "\n")
segs = result.get("segments") or []
lines = []
for i, seg in enumerate(segs, 1):
    # upstream: [start_frame, end_frame, text] OR dicts
    if isinstance(seg, dict):
        start, end, t = float(seg.get("start", 0)), float(seg.get("end", 0)), (seg.get("text") or "").strip()
    elif isinstance(seg, (list, tuple)) and len(seg) >= 3:
        start, end, t = float(seg[0]), float(seg[1]), str(seg[2]).strip()
        # frames at 100Hz? if values look like frames (>1000 for short clip), divide
        if end > 120:
            start, end = start / 100.0, end / 100.0
    else:
        continue
    lines.append(f"{i}\n{ts(start)} --> {ts(end)}\n{t}\n")
open(f"{out}/transcript.srt", "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  fail_runtime "lightning-whisper-mlx exited $rc (segfault on mlx 0.32 is expected; package last released 2024)"
fi

if [[ ! -s "$OUT/transcript.txt" ]]; then
  fail_runtime "empty transcript"
fi
write_asr_status ok
write_bench ok "${WALL:-0}" "${RSS_MB:-0}" mlx
echo "lightning_mlx done wall=${WALL:-?}s rss=${RSS_MB:-?}MB"
