#!/usr/bin/env bash
# Keep transcript/analysis; drop bulky media. Never a wiki tree. Never auto-file.
# Default is dry-run. Pass --apply to delete.
# See docs/retention.md
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
JOBS=${GHOST_JOBS:-${GHOST_WORK:-"$ROOT/jobs"}}
APPLY=0
TTL=
KEEP_MEDIA=0
DROP_FRAMES=0
INCLUDE_SMOKE=0
INCLUDE_BENCH=0
DROP_COOKIES=0
JOB_FILTER=

usage() {
  echo "usage: purge.sh [--apply] [--ttl DAYS] [--keep-media] [--drop-frames]" >&2
  echo "                [--include-smoke] [--include-bench] [--drop-cookies] [--jobs ID]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --dry-run) APPLY=0 ;;
    --ttl) TTL=${2:?}; shift ;;
    --keep-media) KEEP_MEDIA=1 ;;
    --drop-frames) DROP_FRAMES=1 ;;
    --include-smoke) INCLUDE_SMOKE=1 ;;
    --include-bench) INCLUDE_BENCH=1 ;;
    --drop-cookies) DROP_COOKIES=1 ;;
    --jobs) JOB_FILTER=${2:?}; shift ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
  shift
done

JOBS=$(cd "$JOBS" 2>/dev/null && pwd) || { echo "no jobs dir: $JOBS" >&2; exit 1; }
case "$JOBS" in
  */brain|*/brain/*) echo "refuse $JOBS" >&2; exit 1 ;;
esac

rel() { printf '%s\n' "${1#"$JOBS"/}"; }

too_new() {
  local dir=$1
  [[ -z "$TTL" ]] && return 1
  local now fin age
  now=$(date +%s)
  fin=$(jq -r '.finished_at // empty' "$dir/MANIFEST.json" 2>/dev/null || true)
  if [[ -n "$fin" ]]; then
    age=$(( now - $(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$fin" +%s 2>/dev/null || date -d "$fin" +%s) ))
  else
    age=$(( now - $(stat -f %m "$dir" 2>/dev/null || stat -c %Y "$dir") ))
  fi
  [[ "$age" -lt $((TTL * 86400)) ]]
}

maybe_rm() {
  local p=$1
  [[ -e "$p" ]] || return 0
  if [[ "$APPLY" == "1" ]]; then
    rm -rf "$p"
    echo "deleted $(rel "$p")"
  else
    echo "dry-run $(rel "$p")"
  fi
}

asr_ok() {
  local s
  s=$(jq -r '.status // .asr.status // empty' "$1/transcript/asr_status.json" 2>/dev/null || true)
  [[ "$s" == "ok" ]]
}

for dir in "$JOBS"/*; do
  [[ -d "$dir" ]] || continue
  base=$(basename "$dir")
  if [[ "$base" == _smoke ]]; then
    [[ "$INCLUDE_SMOKE" == "1" ]] || continue
    maybe_rm "$dir"
    continue
  fi
  if [[ "$base" == _bench ]]; then
    [[ "$INCLUDE_BENCH" == "1" ]] || continue
    maybe_rm "$dir"
    continue
  fi
  [[ "$base" == _* ]] && continue
  [[ -n "$JOB_FILTER" && "$base" != "$JOB_FILTER" ]] && continue
  [[ -f "$dir/MANIFEST.json" ]] || continue
  too_new "$dir" && continue
  if asr_ok "$dir"; then
    if [[ "$KEEP_MEDIA" != "1" ]]; then
      find "$dir/source" -maxdepth 1 \( \
          -name 'video.*' -o -name 'audio.wav' -o -name 'audio.webm' \
          -o -name 'audio.m4a' -o -name 'audio.opus' -o -name 'audio.mp3' \
          -o -name 'audio.mp4' -o -name 'audio.ogg' -o -name 'audio.flac' \
          -o -name 'audio.mka' \
        \) -type f 2>/dev/null | while read -r p; do maybe_rm "$p"; done
      maybe_rm "$dir/transcript/pass1"
    fi
    [[ "$DROP_FRAMES" == "1" ]] && maybe_rm "$dir/frames"
  fi
done

if [[ "$DROP_COOKIES" == "1" ]]; then
  maybe_rm "$JOBS/cookies.txt"
fi

[[ "$APPLY" == "1" ]] || echo "dry-run only; pass --apply to delete"
