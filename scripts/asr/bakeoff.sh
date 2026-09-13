#!/usr/bin/env bash
# Serial ASR bake-off: whisper.cpp vs mlx-whisper large-v3.
# usage: bakeoff.sh [easy|medium|hard|translate|all]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
OUT_ROOT=$ROOT/work/_bakeoff
SPEC=$ROOT/scripts/asr/bakeoff_spec.json
LOG=$OUT_ROOT/bakeoff.log
FORCE=${GHOST_BAKEOFF_FORCE:-0}
RSS_LIMIT=${GHOST_BAKEOFF_RSS_LIMIT:-12000}
mkdir -p "$OUT_ROOT"

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG"; }

LEVEL_ARG=${1:-all}

# arm|adapter|model
ALL_ARMS=(
  "cpp-prod|scripts/asr/whisper_cpp.sh|ggml-small.en.bin"
  "cpp-large|scripts/asr/whisper_cpp.sh|ggml-large-v3.bin"
  "mlx-bf16|scripts/asr/mlx_whisper.sh|mlx-community/whisper-large-v3-mlx"
  "mlx-8bit|scripts/asr/mlx_whisper.sh|mlx-community/whisper-large-v3-mlx-8bit"
)
ARMS=()
if [[ -n "${GHOST_BAKEOFF_ARMS:-}" ]]; then
  IFS=',' read -r -a _want <<<"$GHOST_BAKEOFF_ARMS"
  for row in "${ALL_ARMS[@]}"; do
    arm=${row%%|*}
    for w in "${_want[@]}"; do
      if [[ "$arm" == "$w" ]]; then ARMS+=("$row"); break; fi
    done
  done
  [[ ${#ARMS[@]} -gt 0 ]] || { echo "no matching GHOST_BAKEOFF_ARMS=$GHOST_BAKEOFF_ARMS" >&2; exit 2; }
else
  ARMS=("${ALL_ARMS[@]}")
fi

levels_for() {
  case "$1" in
    easy) echo easy ;;
    medium) echo medium ;;
    hard) echo hard-broadcast ;;
    translate) echo translate ;;
    translate-langs) echo translate-es translate-fr translate-zh translate-hi translate-en ;;
    all) echo easy medium hard-broadcast translate ;;
    hard-broadcast|translate-es|translate-fr|translate-zh|translate-hi|translate-en) echo "$1" ;;
    *) echo "usage: bakeoff.sh easy|medium|hard|translate|translate-langs|all" >&2; exit 2 ;;
  esac
}

spec_field() {
  python3 - "$SPEC" "$1" "$2" <<'PY'
import json, sys
spec, level, field = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.load(open(spec))[level][field])
PY
}

run_pass() {
  local level=$1 arm=$2 adapter=$3 model=$4 wav=$5 lang=$6 task=$7 pass=$8
  local dest=$OUT_ROOT/$level/$arm/$pass
  mkdir -p "$dest"
  if [[ "$FORCE" != "1" && -s "$dest/bench.json" && -s "$dest/transcript.txt" ]]; then
    if ! grep -qx '\[transcript unavailable\]' "$dest/transcript.txt" 2>/dev/null; then
      log "skip $level $arm $pass (exists)"
      return 0
    fi
  fi
  log "RUN $level $arm $pass model=$model lang=$lang task=$task"
  set +e
  GHOST_WHISPER_LANG=$lang GHOST_WHISPER_TASK=$task \
    env -u GHOST_WHISPER_PROMPT -u GHOST_LEXICON \
    "$ROOT/$adapter" "$wav" "$dest" "$model" >>"$LOG" 2>&1
  local rc=$?
  set -e
  local status=ok
  if [[ $rc -ne 0 ]]; then
    status=failed
  elif [[ ! -s "$dest/transcript.txt" ]] || grep -qx '\[transcript unavailable\]' "$dest/transcript.txt"; then
    status=failed
  fi
  if [[ -f "$dest/bench.json" ]]; then
    local rss
    rss=$(python3 -c "import json; print(json.load(open('$dest/bench.json')).get('peak_rss_mb') or 0)")
    python3 -c "import sys; sys.exit(0 if float('$rss') > float('$RSS_LIMIT') else 1)" && status=oom || true
  fi
  log "DONE $level $arm $pass status=$status rc=$rc"
  if [[ "$status" == "oom" ]]; then
    log "OOM $level $arm $pass rss over ${RSS_LIMIT}MB — continuing"
  fi
}

run_level() {
  local level=$1
  local wav lang task
  wav=$ROOT/$(spec_field "$level" wav)
  lang=$(spec_field "$level" lang)
  task=$(spec_field "$level" task)
  if [[ ! -s "$wav" ]]; then
    log "SKIP missing wav $wav"
    return 0
  fi
  local row arm adapter model
  for row in "${ARMS[@]}"; do
    IFS='|' read -r arm adapter model <<<"$row"
    run_pass "$level" "$arm" "$adapter" "$model" "$wav" "$lang" "$task" cold
    run_pass "$level" "$arm" "$adapter" "$model" "$wav" "$lang" "$task" warm
  done
  python3 "$ROOT/scripts/asr/score_bakeoff.py" "$level" | tee -a "$LOG"
}

FAIL=0
for level in $(levels_for "$LEVEL_ARG"); do
  run_level "$level" || FAIL=1
done
python3 "$ROOT/scripts/asr/score_bakeoff.py" $(levels_for "$LEVEL_ARG") >/dev/null || true
if [[ "$FAIL" -ne 0 ]]; then
  log "BAKEOFF $LEVEL_ARG FAILED"
  exit 1
fi
log "BAKEOFF $LEVEL_ARG PASSED"
exit 0
