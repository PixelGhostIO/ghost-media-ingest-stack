#!/usr/bin/env bash
# Mac (supported): ./scripts/bootstrap.sh --host
#   Homebrew ffmpeg (must list videotoolbox), whisper-cpp (Metal), yt-dlp, jq.
# CPU fallback:     ./scripts/bootstrap.sh          # Docker image only
# Does not install Docker Desktop.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
HOST=0
for a in "$@"; do
  [[ "$a" == "--host" ]] && HOST=1
done

if [[ "$HOST" == "1" ]]; then
  if ! command -v brew >/dev/null; then
    echo "--host needs Homebrew." >&2
    exit 1
  fi
  for f in ffmpeg whisper-cpp yt-dlp jq; do
    if brew list "$f" >/dev/null 2>&1; then
      echo "brew: $f already installed"
    else
      brew install "$f" || true
    fi
  done
  echo "host ffmpeg: $(command -v ffmpeg)"
  echo "host whisper-cli: $(command -v whisper-cli)"
  hw=$(ffmpeg -hide_banner -hwaccels 2>/dev/null || true)
  echo "$hw"
  if ! printf '%s\n' "$hw" | grep -qx 'videotoolbox'; then
    echo "ffmpeg must list videotoolbox (Homebrew build with --enable-videotoolbox)." >&2
    echo "Try: brew reinstall ffmpeg" >&2
    exit 1
  fi
  echo "Mac ingest: ./scripts/ingest.sh '<url>'"
  exit 0
fi

if ! command -v docker >/dev/null; then
  echo "docker is not installed. On a Mac use: ./scripts/bootstrap.sh --host" >&2
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose is required for the CPU image." >&2
  exit 1
fi
docker compose build
echo "image built (Linux whisper-cli is CPU-only; no Metal/VideoToolbox in the container)."
docker compose run --rm ingest smoke easy
echo "Docker ingest: docker compose run --rm ingest '<url>'"
