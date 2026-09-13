#!/usr/bin/env bash
# smoke easy|medium|hard — host ffmpeg + Metal whisper on Mac
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
INGEST=$SCRIPT_DIR/ingest.sh
LEVEL=${1:-easy}
WORK_ROOT=${GHOST_JOBS:-${GHOST_WORK:-$ROOT/jobs}}
FAIL=0
GBRAIN=${GBRAIN:-}
[[ -n "$GBRAIN" && -x "$GBRAIN" ]] || GBRAIN=$(command -v gbrain || true)

ok() { printf 'PASS %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; FAIL=1; }

need_bin() {
  command -v "$1" >/dev/null || bad "missing binary $1 — ./scripts/bootstrap.sh --host"
}

assert_file() {
  [[ -s "$1" ]] && ok "file $1" || bad "missing/empty $1"
}

assert_json() {
  jq -e "$2" "$1" >/dev/null 2>&1 && ok "jq $2 $1" || bad "jq $2 failed on $1"
}

ingest_one() {
  local url=$1 dest=$2
  mkdir -p "$dest"
  GHOST_JOBS=$dest GHOST_WORK=$dest "$INGEST" "$url"
}

need_bin ffmpeg
need_bin ffprobe
need_bin yt-dlp
need_bin jq
need_bin curl
if [[ "$LEVEL" != "easy" ]]; then
  need_bin whisper-cli
fi
if [[ "$FAIL" -ne 0 ]]; then
  echo "SMOKE $LEVEL FAILED"
  exit 1
fi

case "$LEVEL" in
  easy)
    DIR=$WORK_ROOT/_smoke/easy
    rm -rf "$DIR"
    mkdir -p "$DIR"
    ffmpeg -y -f lavfi -i testsrc=duration=2:size=640x360:rate=25 \
           -f lavfi -i sine=frequency=440:duration=2 \
           -shortest -pix_fmt yuv420p "$DIR/easy.mp4" </dev/null
    GHOST_JOBS=$DIR/out GHOST_WORK=$DIR/out GHOST_SKIP_ASR=1 \
      "$INGEST" "$DIR/easy.mp4"
    JOB=$(find "$DIR/out" -mindepth 1 -maxdepth 1 -type d | head -1)
    [[ -n "$JOB" ]] || { bad "no job dir"; echo "SMOKE easy FAILED"; exit 1; }
    assert_file "$JOB/source/audio.wav"
    RATE=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate,channels \
           -of csv=p=0 "$JOB/source/audio.wav" || true)
    [[ "$RATE" == 16000,1 ]] && ok "wav 16k mono" || bad "wav not 16k mono ($RATE)"
    N=$(find "$JOB/frames" -name 'scene-*.jpg' | wc -l | tr -d ' ')
    [[ "$N" -ge 1 ]] && ok "frames=$N" || bad "need ≥1 frame"
    assert_file "$JOB/MANIFEST.json"
    assert_json "$JOB/MANIFEST.json" '.status=="ok" and .id!=null'
    grep -q 'STAGE audio' "$JOB/pipeline.log" && ok "log stages" || bad "pipeline.log stages"
    grep -q 'STAGE captions' "$JOB/pipeline.log" && ok "captions stage" || bad "no captions stage"
    assert_file "$JOB/transcript/captions_status.json"
    assert_json "$JOB/transcript/captions_status.json" '.kind=="none"'
    assert_file "$JOB/transcript/canonical.en.txt"
    ;;
  medium)
    URL=${GHOST_SMOKE_URL:-https://www.youtube.com/watch?v=PeMlggyqz0Y}
    DEST=$WORK_ROOT/_smoke/medium
    rm -rf "$DEST"
    ingest_one "$URL" "$DEST"
    JOB=$(find "$DEST" -mindepth 1 -maxdepth 1 -type d ! -name '_*' | head -1)
    [[ -n "$JOB" ]] || { bad "no job dir"; echo "SMOKE medium FAILED"; exit 1; }
    assert_file "$JOB/source/audio.wav"
    assert_file "$JOB/transcript/transcript.txt"
    [[ -s "$JOB/transcript/transcript.txt" ]] && ! grep -qx '\[transcript unavailable\]' "$JOB/transcript/transcript.txt" \
      && ok "transcript non-empty" || bad "transcript empty/unavailable"
    assert_json "$JOB/transcript/asr_status.json" '.status=="ok"'
    THUMB=$(find "$JOB/source" -name '*.jpg' | head -1 || true)
    [[ -n "$THUMB" ]] && ok "thumbnail" || bad "no thumbnail"
    WANT_ID=$(jq -r '.id' "$JOB/MANIFEST.json")
    [[ "$WANT_ID" == "PeMlggyqz0Y" || -n "${GHOST_SMOKE_URL:-}" ]] && ok "id=$WANT_ID" || bad "unexpected id $WANT_ID"
    ;;
  hard)
    DEST=$WORK_ROOT/_smoke/hard
    rm -rf "$DEST"
    mkdir -p "$DEST"
    START=$(date +%s)
    U1=${GHOST_SMOKE_URL:-https://www.youtube.com/watch?v=PeMlggyqz0Y}
    U2=${GHOST_SMOKE_URL_2:-https://www.youtube.com/watch?v=i8NETqtGHms}
    ingest_one "$U1" "$DEST"
    ingest_one "$U2" "$DEST"
    END=$(date +%s)
    echo "hard ingest_wall_seconds=$((END-START))"
    NJOBS=$(find "$DEST" -mindepth 1 -maxdepth 1 -type d ! -name '_*' | wc -l | tr -d ' ')
    [[ "$NJOBS" -eq 2 ]] && ok "two jobs" || bad "expected 2 jobs got $NJOBS"
    for JOB in "$DEST"/*; do
      [[ -d "$JOB" ]] || continue
      assert_file "$JOB/transcript/transcript.txt"
      assert_file "$JOB/transcript/transcript.srt"
      assert_json "$JOB/transcript/asr_status.json" '.status=="ok"'
      N=$(find "$JOB/frames" -name 'scene-*.jpg' | wc -l | tr -d ' ')
      [[ "$N" -ge 1 ]] && ok "$(basename "$JOB") frames=$N" || bad "$(basename "$JOB") need ≥1 frame"
    done
    Q="Compare these two short AI explainers (machine learning vs TensorFlow). Context, overlap, and practical applications for an agent that ingests video. Do not invent quotes."
    export GBRAIN_NO_BRAINSTORM_PREVIEW=1
    gbrain_to() {
      local out=$1 err=$2; shift 2
      python3 - "$out" "$err" "$@" <<'PY'
import subprocess, sys, os
out, err, *cmd = sys.argv[1:]
try:
    r = subprocess.run(cmd, stdout=open(out,"w"), stderr=open(err,"w"), timeout=90)
    sys.exit(r.returncode)
except subprocess.TimeoutExpired:
    open(err,"a").write("\ntimeout 90s\n")
    sys.exit(124)
PY
    }
    if [[ -n "$GBRAIN" && -x "$GBRAIN" ]]; then
      set +e
      gbrain_to "$DEST/brainstorm.json" "$DEST/brainstorm.err" \
        "$GBRAIN" brainstorm "$Q" --no-save --yes --json --limit 3 --max-cost 2
      br=$?
      gbrain_to "$DEST/lsd.json" "$DEST/lsd.err" \
        "$GBRAIN" lsd "$Q" --yes --json --limit 3 --max-cost 2
      ls=$?
      set -e
      if [[ $br -eq 0 && -s $DEST/brainstorm.json ]]; then ok "gbrain brainstorm"; else echo "gbrain: skipped brainstorm ($br)" | tee -a "$DEST/gbrain.status"; ok "brainstorm skipped"; fi
      if [[ $ls -eq 0 && -s $DEST/lsd.json ]]; then ok "gbrain lsd"; else echo "gbrain: skipped lsd ($ls)" | tee -a "$DEST/gbrain.status"; ok "lsd skipped"; fi
    else
      echo "gbrain: skipped (no gbrain binary)" | tee "$DEST/gbrain.status"
      ok "gbrain optional skip"
    fi
    {
      echo "# hard smoke mash-up"
      echo
      echo "- videos: $U1 and $U2"
      echo "- ingest wall_s: $((END-START))"
      echo "- gbrain brainstorm: $([[ -s $DEST/brainstorm.json ]] && echo ok || echo skipped)"
      echo "- gbrain lsd: $([[ -s $DEST/lsd.json ]] && echo ok || echo skipped)"
      echo
      echo "Not filed to a wiki. Transcripts stay in this job dir."
    } >"$DEST/REPORT.md"
    assert_file "$DEST/REPORT.md"
    ;;
  *)
    echo "usage: smoke.sh easy|medium|hard" >&2
    exit 2
    ;;
esac

if [[ "$FAIL" -ne 0 ]]; then
  echo "SMOKE $LEVEL FAILED"
  exit 1
fi
echo "SMOKE $LEVEL PASSED"
