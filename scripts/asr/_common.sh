#!/usr/bin/env bash
# Shared helpers for scripts/asr/*.sh
# Contract: WAV OUT_DIR [MODEL]
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
VENV=$ROOT/.venv
export PATH="$VENV/bin:/opt/homebrew/bin:$PATH"

write_bench() {
  local status=$1 wall=$2 rss=$3 device=$4 extra=${5:-{}}
  python3 - "$OUT" "$RUNTIME" "$MODEL" "$status" "$wall" "$rss" "$device" "$WAV" <<'PY'
import json, os, sys
out, runtime, model, status, wall, rss, device, wav = sys.argv[1:9]
dur = 0.0
try:
    import subprocess
    dur = float(subprocess.check_output(
        ["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0", wav],
        text=True).strip() or 0)
except Exception:
    pass
wall_f = float(wall or 0)
rtf = (dur / wall_f) if wall_f > 0 else 0
doc = {
  "status": status,
  "runtime": runtime,
  "model": model,
  "device": device,
  "wall_s": wall_f,
  "audio_s": dur,
  "rtf": round(rtf, 3),
  "peak_rss_mb": float(rss or 0),
}
print(json.dumps(doc, indent=2))
open(os.path.join(out, "bench.json"), "w").write(json.dumps(doc, indent=2) + "\n")
PY
}

write_asr_status() {
  local status=$1
  python3 -c "import json,sys; print(json.dumps({'status':sys.argv[1],'model':sys.argv[2],'runtime':sys.argv[3]}))" \
    "$status" "$MODEL" "$RUNTIME" >"$OUT/asr_status.json"
}

fail_runtime() {
  local msg=$1
  mkdir -p "$OUT"
  printf '%s\n' "$msg" | tee "$OUT/error.log"
  printf '%s\n' '[transcript unavailable]' >"$OUT/transcript.txt"
  : >"$OUT/transcript.srt"
  write_asr_status failed
  write_bench failed 0 0 unknown
  exit 0
}

time_cmd() {
  # macOS /usr/bin/time -l → peak RSS in bytes on "maximum resident set size"
  local tfile=$OUT/time.txt
  /usr/bin/time -l -o "$tfile" "$@"
  WALL=$(awk '/real/{print $1}' "$tfile" | tail -1)
  # GNU time prints elapsed as 0.12; BSD time -l uses "real" in some versions.
  # BSD /usr/bin/time -l: first line is like "        0.12 real         0.05 user..."
  WALL=$(awk 'NR==1{for(i=1;i<=NF;i++) if($i=="real") print $(i-1)}' "$tfile")
  RSS_BYTES=$(awk '/maximum resident set size/{print $1}' "$tfile")
  RSS_MB=$(python3 -c "print(round(int('${RSS_BYTES:-0}')/1024/1024, 1))")
}

need() {
  command -v "$1" >/dev/null || fail_runtime "missing binary $1"
}
