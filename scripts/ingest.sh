#!/usr/bin/env bash
# Deterministic video ingest. Judgment (context/meaning/intent) is the agent's job.
# See docs/pipeline.md
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LOG=/dev/stderr

if [[ "${1:-}" == "smoke" ]]; then
  exec "$SCRIPT_DIR/smoke.sh" "${2:-easy}"
fi

if [[ $# -lt 1 ]]; then
  echo "usage: ingest.sh <url-or-file>" >&2
  echo "       ingest.sh smoke easy|medium|hard" >&2
  exit 2
fi

SRC=$1
# GHOST_JOBS is the processing root (jobs/<id>/). GHOST_WORK is a deprecated alias.
JOBS_ROOT=${GHOST_JOBS:-${GHOST_WORK:-jobs}}
WORK_ROOT=$JOBS_ROOT
MODELS=${GHOST_MODELS:-$SCRIPT_DIR/../models}
WHISPER_MODEL=${GHOST_WHISPER_MODEL:-ggml-base.en.bin}
SKIP_ASR=${GHOST_SKIP_ASR:-0}
GHOST_ASR=${GHOST_ASR:-whisper_cpp}
AUTO_PROMPT=${GHOST_AUTO_PROMPT:-0}
DO_PURGE=${GHOST_PURGE:-0}
NO_FRAMES=${GHOST_NO_FRAMES:-0}
ANALYZE_FRAMES=${GHOST_ANALYZE_FRAMES:-0}
SKIP_CAPTIONS=${GHOST_SKIP_CAPTIONS:-0}
SUB_LANGS=${GHOST_SUB_LANGS:-all,-live_chat}
YT_PLAYER_CLIENT=${GHOST_YT_PLAYER_CLIENT:-web,default}
SUB_SKIP_TRANSLATED=${GHOST_SUB_SKIP_TRANSLATED:-1}
SKIP_ASR_IF_MANUAL_EN=${GHOST_SKIP_ASR_IF_MANUAL_EN:-0}
PROMPT_SRC=${GHOST_PROMPT:-$SCRIPT_DIR/../prompts/understand.md}
HF_BASE=https://huggingface.co/ggerganov/whisper.cpp/resolve/main

mkdir -p "$WORK_ROOT" "$MODELS"

log() { printf '%s\n' "$*" | tee -a "$LOG"; }
stage() {
  STAGE=$1
  log "STAGE ${STAGE}"
}

die() {
  log "ERROR: $*"
  if [[ -n "${JOB:-}" ]]; then
    jq -n --arg err "$*" --arg stage "${STAGE:-}" '{status:"failed",stage:$stage,error:$err}' >"$JOB/status.json" || true
  fi
  exit 1
}

if [[ "${GHOST_DOCKER:-0}" != "1" ]]; then
  for b in ffmpeg ffprobe yt-dlp jq; do
    command -v "$b" >/dev/null || die "missing $b — on a Mac run ./scripts/bootstrap.sh --host"
  done
  if [[ "$SKIP_ASR" != "1" ]]; then
    command -v whisper-cli >/dev/null || die "missing whisper-cli — on a Mac run ./scripts/bootstrap.sh --host"
  fi
fi

is_url() { [[ "$1" =~ ^https?:// ]]; }

# Shared yt-dlp flags for resolve + fetch (Vimeo/embeds/cookies).
ytdlp_common() {
  YTDLP_COMMON=(--no-playlist --no-mtime --playlist-items "${GHOST_PLAYLIST_ITEMS:-1}")
  if [[ -f "$JOBS_ROOT/cookies.txt" ]]; then
    YTDLP_COMMON+=(--cookies "$JOBS_ROOT/cookies.txt")
  elif [[ -n "${GHOST_COOKIES:-}" && -f "$GHOST_COOKIES" ]]; then
    YTDLP_COMMON+=(--cookies "$GHOST_COOKIES")
  fi
  if [[ -n "${GHOST_REFERER:-}" ]]; then
    YTDLP_COMMON+=(--referer "$GHOST_REFERER")
  fi
  if [[ "${GHOST_FORCE_GENERIC:-0}" == "1" ]]; then
    YTDLP_COMMON+=(--ies generic,default)
  fi
  if [[ -n "${GHOST_VIDEO_PASSWORD:-}" ]]; then
    YTDLP_COMMON+=(--video-password "$GHOST_VIDEO_PASSWORD")
  fi
}

# --- resolve id/title without downloading ---
stage_resolve() {
  stage resolve
  local print_json
  ytdlp_common
  if is_url "$SRC"; then
    print_json=$(yt-dlp "${YTDLP_COMMON[@]}" --skip-download --print '%(.{id,title,channel,duration,upload_date,webpage_url,language})j' "$SRC") \
      || die "yt-dlp resolve failed for $SRC"
    ID=$(printf '%s' "$print_json" | jq -r '.id // empty')
    TITLE=$(printf '%s' "$print_json" | jq -r '.title // ""')
    CHANNEL=$(printf '%s' "$print_json" | jq -r '.channel // ""')
    DURATION=$(printf '%s' "$print_json" | jq -r '.duration // 0')
    UPLOAD_DATE=$(printf '%s' "$print_json" | jq -r '.upload_date // ""')
    PAGE_URL=$(printf '%s' "$print_json" | jq -r --arg s "$SRC" '.webpage_url // $s')
  else
    [[ -f "$SRC" ]] || die "not a url or file: $SRC"
    ID=$(basename "$SRC")
    ID=${ID%.*}
    TITLE=$ID
    CHANNEL=""
    DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$SRC" | cut -d. -f1)
    DURATION=${DURATION:-0}
    UPLOAD_DATE=""
    PAGE_URL=$SRC
    print_json=$(jq -n --arg id "$ID" --arg title "$TITLE" --argjson duration "$DURATION" \
      '{id:$id,title:$title,channel:"",duration:$duration,upload_date:"",webpage_url:""}')
  fi
  [[ -n "$ID" ]] || die "could not resolve media id"
  JOB=$WORK_ROOT/$ID
  rm -rf "$JOB"
  mkdir -p "$JOB/source" "$JOB/transcript" "$JOB/frames" "$JOB/analysis"
  LOG=$JOB/pipeline.log
  : >"$LOG"
  log "STAGE resolve"
  log "id=$ID title=$TITLE duration=$DURATION"
  printf '%s\n' "$print_json" >"$JOB/source/yt-dlp-print.json"
}

stage_fetch() {
  stage fetch
  ytdlp_common
  if is_url "$SRC"; then
    yt-dlp "${YTDLP_COMMON[@]}" \
      --write-info-json \
      --write-description \
      --write-thumbnail \
      --convert-thumbnails jpg \
      -f 'bestaudio/best' \
      -o "$JOB/source/audio.%(ext)s" \
      "$SRC" || die "audio fetch failed"

    if [[ "$NO_FRAMES" != "1" ]]; then
      yt-dlp "${YTDLP_COMMON[@]}" \
        -f 'bestvideo[height<=720]/best[height<=720]/best' \
        -o "$JOB/source/video.%(ext)s" \
        "$SRC" || log "WARN: video fetch failed; frames may be skipped"
    fi
  else
    [[ -f "$SRC" ]] || die "not a url or file: $SRC"
    local ext=${SRC##*.}
    cp -f "$SRC" "$JOB/source/video.${ext}"
    ffmpeg -y -i "$SRC" -vn -acodec copy "$JOB/source/audio.${ext}" 2>/dev/null \
      || ffmpeg -y -i "$SRC" "$JOB/source/audio.wav"
  fi

  # yt-dlp also writes audio.info.json / .description / thumbnails as audio.*
  local a
  a=$(find "$JOB/source" -maxdepth 1 \( \
      -name 'audio.wav' -o -name 'audio.webm' -o -name 'audio.m4a' \
      -o -name 'audio.opus' -o -name 'audio.mp3' -o -name 'audio.mp4' \
      -o -name 'audio.ogg' -o -name 'audio.flac' -o -name 'audio.mka' \
    \) | head -1 || true)
  [[ -n "$a" ]] || die "no audio file after fetch"
  AUDIO_IN=$a
}

caption_extractor_args() {
  local args="youtube:player_client=${YT_PLAYER_CLIENT}"
  if [[ "$SUB_SKIP_TRANSLATED" == "1" ]]; then
    args="${args};skip=translated_subs"
  fi
  printf '%s' "$args"
}

stage_captions() {
  stage captions
  mkdir -p "$JOB/source/captions/manual" "$JOB/source/captions/auto"
  if [[ "$SKIP_CAPTIONS" == "1" ]]; then
    log "captions skipped (GHOST_SKIP_CAPTIONS=1)"
  elif ! is_url "$SRC"; then
    log "captions skipped (local file)"
  else
    ytdlp_common
    local ex
    ex=$(caption_extractor_args)
    set +e
    yt-dlp "${YTDLP_COMMON[@]}" --skip-download \
      --write-subs --no-write-auto-subs \
      --sub-langs "$SUB_LANGS" \
      --sub-format vtt/best --convert-subs srt \
      --extractor-args "$ex" \
      -o "subtitle:$JOB/source/captions/manual/%(language)s.%(ext)s" \
      "$SRC" >>"$LOG" 2>&1
    yt-dlp "${YTDLP_COMMON[@]}" --skip-download \
      --no-write-subs --write-auto-subs \
      --sub-langs "$SUB_LANGS" \
      --sub-format vtt/best --convert-subs srt \
      --extractor-args "$ex" \
      -o "subtitle:$JOB/source/captions/auto/%(language)s.%(ext)s" \
      "$SRC" >>"$LOG" 2>&1
    set -e
  fi
  if command -v python3 >/dev/null; then
    python3 "$SCRIPT_DIR/asr/canonical.py" status "$JOB" >/dev/null || log "WARN: captions status failed"
  fi
  if [[ "$SKIP_ASR_IF_MANUAL_EN" == "1" ]]; then
    local kind
    kind=$(jq -r '.kind // "none"' "$JOB/transcript/captions_status.json" 2>/dev/null || echo none)
    if [[ "$kind" == "manual" ]]; then
      SKIP_ASR=1
      log "asr skip (GHOST_SKIP_ASR_IF_MANUAL_EN=1 and manual EN captions)"
    fi
  fi
}

stage_canonical() {
  stage canonical
  if command -v python3 >/dev/null; then
    python3 "$SCRIPT_DIR/asr/canonical.py" choose "$JOB" >/dev/null || log "WARN: canonical choose failed"
  fi
  if [[ ! -s "$JOB/transcript/canonical.en.txt" ]]; then
    if [[ -s "$JOB/transcript/transcript.txt" ]]; then
      cp -f "$JOB/transcript/transcript.txt" "$JOB/transcript/canonical.en.txt"
    else
      printf '%s\n' '[transcript unusable]' >"$JOB/transcript/canonical.en.txt"
    fi
    jq -n '{source:"whisper_en",reason:["chooser-missing"]}' >"$JOB/transcript/canonical.json" 2>/dev/null || true
  fi
}

stage_audio() {
  stage audio
  ffmpeg -y -i "$AUDIO_IN" -ac 1 -ar 16000 -vn "$JOB/source/audio.wav" </dev/null
  [[ -s "$JOB/source/audio.wav" ]] || die "audio.wav missing"
}

stage_frames() {
  stage frames
  if [[ "$NO_FRAMES" == "1" ]]; then
    log "frames skipped (GHOST_NO_FRAMES=1)"
    return 0
  fi
  local v
  v=$(find "$JOB/source" -maxdepth 1 -name 'video.*' | head -1 || true)
  if [[ -z "$v" ]]; then
    log "WARN: no video; skipping frames"
    return 0
  fi
  # Prefer VideoToolbox decode on macOS host; never re-encode. Fall back to CPU.
  local ffdec=(ffmpeg -y -hide_banner -loglevel error)
  if [[ "$(uname -s)" == Darwin ]] && ffmpeg -hide_banner -hwaccels 2>/dev/null | grep -qx videotoolbox; then
    ffdec+=( -hwaccel videotoolbox )
    log "ffmpeg decode: videotoolbox"
  fi
  "${ffdec[@]}" -i "$v" \
    -vf "select='gt(scene,0.30)',scale='min(1280,iw)':-2" \
    -fps_mode vfr -frames:v 24 \
    "$JOB/frames/scene-%04d.jpg" </dev/null || \
  ffmpeg -y -hide_banner -loglevel error -i "$v" \
    -vf "select='gt(scene,0.30)',scale='min(1280,iw)':-2" \
    -fps_mode vfr -frames:v 24 \
    "$JOB/frames/scene-%04d.jpg" </dev/null || true
  local n
  n=$(find "$JOB/frames" -name 'scene-*.jpg' | wc -l | tr -d ' ')
  if [[ "$n" -eq 0 ]]; then
    log "scene detect empty; fps=1 fallback"
    ffmpeg -y -i "$v" -vf "fps=1,scale='min(1280,iw)':-2" -frames:v 24 \
      "$JOB/frames/scene-%04d.jpg" </dev/null || true
  fi
  n=$(find "$JOB/frames" -name 'scene-*.jpg' | wc -l | tr -d ' ')
  if [[ "$n" -eq 0 ]]; then
    log "fps=1 empty; first-frame fallback"
    ffmpeg -y -ss 0 -i "$v" -frames:v 1 "$JOB/frames/scene-0001.jpg" </dev/null || true
  fi
  n=$(find "$JOB/frames" -name 'scene-*.jpg' | wc -l | tr -d ' ')
  log "frames=$n"
}

ensure_model() {
  local name=$1
  local dest=$MODELS/$name
  if [[ -f "$dest" ]]; then
    echo "$dest"
    return
  fi
  log "downloading whisper model $name"
  curl -fsSL "$HF_BASE/$name" -o "$dest"
  echo "$dest"
}

asr_once() {
  local adapter=$SCRIPT_DIR/asr/${GHOST_ASR}.sh
  if [[ -x "$adapter" && "${GHOST_DOCKER:-0}" != "1" ]]; then
    log "asr host adapter $GHOST_ASR"
    "$adapter" "$JOB/source/audio.wav" "$JOB/transcript" "${GHOST_WHISPER_MODEL:-}"
    return 0
  fi
  local model_path prefix prompt_args=()
  model_path=$(ensure_model "$WHISPER_MODEL") || die "whisper model download failed"
  if [[ -n "${GHOST_WHISPER_PROMPT:-}" ]]; then
    local ptext
    if [[ -f "$GHOST_WHISPER_PROMPT" ]]; then
      ptext=$(cat "$GHOST_WHISPER_PROMPT")
    else
      ptext=$GHOST_WHISPER_PROMPT
    fi
    [[ -n "$ptext" ]] && prompt_args=(--prompt "$ptext")
  fi
  prefix=$JOB/transcript/whisper
  if ! whisper-cli -m "$model_path" -f "$JOB/source/audio.wav" -otxt -osrt -oj -of "$prefix" -l en "${prompt_args[@]}"; then
    jq -n --arg model "$WHISPER_MODEL" '{status:"failed",model:$model}' >"$JOB/transcript/asr_status.json"
    die "whisper-cli failed"
  fi
  if [[ -f ${prefix}.txt ]]; then mv -f "${prefix}.txt" "$JOB/transcript/transcript.txt"; fi
  if [[ -f ${prefix}.srt ]]; then mv -f "${prefix}.srt" "$JOB/transcript/transcript.srt"; fi
  if [[ -f ${prefix}.json ]]; then mv -f "${prefix}.json" "$JOB/transcript/whisper.json"; fi
  if [[ ! -s "$JOB/transcript/transcript.txt" ]]; then
    jq -n --arg model "$WHISPER_MODEL" '{status:"empty",model:$model}' >"$JOB/transcript/asr_status.json"
    log "WARN: transcript empty — leaving [transcript unavailable]"
    printf '%s\n' '[transcript unavailable]' >"$JOB/transcript/transcript.txt"
  else
    jq -n --arg model "$WHISPER_MODEL" --arg lang en '{status:"ok",model:$model,language:$lang}' >"$JOB/transcript/asr_status.json"
  fi
}

stage_asr() {
  stage asr
  if [[ "$SKIP_ASR" == "1" ]]; then
    log "asr skipped (GHOST_SKIP_ASR=1)"
    jq -n --arg model "$WHISPER_MODEL" '{status:"skipped",model:$model}' >"$JOB/transcript/asr_status.json"
    return 0
  fi
  asr_once
  if [[ "$AUTO_PROMPT" != "1" ]]; then
    return 0
  fi
  local py=$SCRIPT_DIR/asr/auto_prompt.py
  command -v python3 >/dev/null || { log "WARN: python3 missing; skip auto-prompt"; return 0; }
  python3 "$py" "$JOB" || { log "WARN: auto_prompt.py failed"; return 0; }
  local ap=$JOB/transcript/auto-prompt.txt
  if [[ ! -s "$ap" ]]; then
    log "auto-prompt empty; skip second pass"
    return 0
  fi
  mkdir -p "$JOB/transcript/pass1"
  for f in transcript.txt transcript.srt whisper.json asr_status.json; do
    [[ -f $JOB/transcript/$f ]] && cp -f "$JOB/transcript/$f" "$JOB/transcript/pass1/"
  done
  export GHOST_WHISPER_PROMPT=$ap
  log "asr second pass with auto-prompt"
  asr_once
}

stage_manifest() {
  stage manifest
  local nframes asr_status
  nframes=$(find "$JOB/frames" -name 'scene-*.jpg' 2>/dev/null | wc -l | tr -d ' ')
  asr_status=$(jq -r '.status' "$JOB/transcript/asr_status.json" 2>/dev/null || echo unknown)
  local af=false
  [[ "$ANALYZE_FRAMES" == "1" ]] && af=true
  jq -n \
    --arg url "$PAGE_URL" \
    --arg src "$SRC" \
    --arg id "$ID" \
    --arg title "$TITLE" \
    --arg channel "$CHANNEL" \
    --arg upload_date "$UPLOAD_DATE" \
    --argjson duration "${DURATION:-0}" \
    --arg ffmpeg "$(ffmpeg -version | head -1)" \
    --arg ytdlp "$(yt-dlp --version)" \
    --arg whisper "$(whisper-cli --help 2>&1 | head -1 || true)" \
    --arg model "$WHISPER_MODEL" \
    --arg asr "$asr_status" \
    --argjson frames "${nframes:-0}" \
    --argjson analyze_frames "$af" \
    --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      status: "ok",
      url: $url,
      source: $src,
      id: $id,
      title: $title,
      channel: $channel,
      duration: $duration,
      upload_date: $upload_date,
      tools: {ffmpeg: $ffmpeg, "yt-dlp": $ytdlp, whisper: $whisper, whisper_model: $model},
      asr: {status: $asr, model: $model},
      frames: $frames,
      analyze_frames: $analyze_frames,
      paths: {
        audio: "source/audio.wav",
        transcript: "transcript/transcript.txt",
        srt: "transcript/transcript.srt",
        asr_status: "transcript/asr_status.json",
        canonical: "transcript/canonical.en.txt",
        captions_status: "transcript/captions_status.json",
        frames: "frames/",
        analysis: "analysis/",
        log: "pipeline.log"
      },
      finished_at: $started
    }' >"$JOB/MANIFEST.json"
  cp "$JOB/MANIFEST.json" "$JOB/status.json"
}

stage_purge_media() {
  [[ "$DO_PURGE" == "1" ]] || return 0
  stage purge
  local asr
  asr=$(jq -r '.status // .asr.status // empty' "$JOB/transcript/asr_status.json" 2>/dev/null || true)
  if [[ "$asr" != "ok" ]]; then
    log "purge skipped (asr=$asr)"
    return 0
  fi
  find "$JOB/source" -maxdepth 1 \( \
      -name 'video.*' -o -name 'audio.wav' -o -name 'audio.webm' \
      -o -name 'audio.m4a' -o -name 'audio.opus' -o -name 'audio.mp3' \
      -o -name 'audio.mp4' -o -name 'audio.ogg' -o -name 'audio.flac' \
      -o -name 'audio.mka' \
    \) -type f -print -delete | while read -r p; do log "purged $p"; done
  rm -rf "$JOB/transcript/pass1"
  log "purge keep-text-drop-media"
}

stage_stop() {
  stage stop
  if [[ -f "$PROMPT_SRC" ]]; then
    cp "$PROMPT_SRC" "$JOB/analysis/understand.md"
  fi
  cat >"$JOB/analysis/README.md" <<EOF
Fill context.md, meaning.md, intent.md from MANIFEST.json + transcript/canonical.en.txt (cite transcript/canonical.json). Whisper-only text stays in transcript/transcript.txt. Do not invent speech.

Do not send frames/ to a vision model unless MANIFEST.analyze_frames is true (GHOST_ANALYZE_FRAMES=1) or the operator asked. ffmpeg stills may exist on disk anyway; that is not permission to spend vision tokens.
EOF
  log "done $JOB"
  printf '%s\n' "$JOB"
}

# pipeline.log does not exist until resolve creates JOB; bootstrap a temp log
LOG=/dev/stderr
STAGE=
ID=
JOB=
TITLE=
CHANNEL=
DURATION=0
UPLOAD_DATE=
PAGE_URL=$SRC
AUDIO_IN=

stage_resolve
stage_fetch
stage_captions
stage_audio
stage_frames
stage_asr
stage_canonical
stage_manifest
stage_purge_media
stage_stop
