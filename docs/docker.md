# Docker

Docker is the **portable CPU** path (Linux/CI). It cannot use Metal, ANE, or VideoToolbox. On a Mac, prefer host Homebrew ffmpeg + `whisper-cli` (`./scripts/bootstrap.sh --host`, then `./scripts/ingest.sh`). We do not re-encode video.

The image still contains ffmpeg, yt-dlp, whisper-cli (whisper.cpp v1.9.2), python3. Builds linux/amd64 and linux/arm64. Docker ffmpeg lists cuda/vaapi in help; those devices are not the Mac GPU.

```bash
docker compose build
docker compose run --rm ingest smoke easy
docker compose run --rm ingest 'https://www.youtube.com/watch?v=VIDEO_ID'
```

Volumes (compose): `./jobs` → `/jobs`, `./models` → `/models`. Whisper weights are not baked in.

First ASR run downloads `ggml-base.en.bin` from Hugging Face into `models/`. Easy smoke skips ASR (`GHOST_SKIP_ASR=1`). Medium/hard download the configured model.

## Smoke

On a Mac, smokes use **host** ffmpeg + Metal whisper:

```bash
./scripts/bootstrap.sh --host
./scripts/smoke.sh easy      # lavfi, no net
./scripts/smoke.sh medium    # ML in 100s (PeMlggyqz0Y)
./scripts/smoke.sh hard      # both PeMlggyqz0Y + i8NETqtGHms (optional wiki CLI if on PATH, 90s cap, not filed)
```

Override clip: `GHOST_SMOKE_URL=https://… docker compose run --rm ingest smoke medium`

Optional public Vimeo (not a required smoke): `GHOST_SMOKE_URL=https://vimeo.com/76979871 docker compose run --rm ingest smoke medium`

Embed-only players: pass the embedding page URL, or `GHOST_REFERER=https://example.com/page`.

## Cookies

Place Netscape cookies at `jobs/cookies.txt` for age-gated URLs.

## Rebuild

```bash
docker compose build --no-cache
```
