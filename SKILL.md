---
name: ghost-media-ingest
description: >
  Fetch an internet video (YouTube first), extract audio and frames with
  ffmpeg/yt-dlp, transcribe with Whisper, then write context / meaning /
  intent. Use when the user shares a video URL, says "process this YouTube",
  "ingest this video", or "ghost media ingest".
triggers:
  - "process this YouTube"
  - "ingest this video"
  - "ghost media ingest"
  - shares a youtube.com or youtu.be URL for understanding
mutating: false
---

# ghost-media-ingest

On a Mac, run ingest on the **host** (Homebrew ffmpeg + Metal `whisper-cli`). Docker is the portable CPU fallback. You write analysis. Pipeline details: `docs/pipeline.md`.

## Contract

- Run ingest from **this repo** (`./scripts/ingest.sh` on Mac, or `docker compose` for CPU).
- Do not invent transcript lines. If ASR is not `ok`, say `[transcript unavailable]`.
- Do not file into a brain unless the operator asked.
- Do not `git push` unless the operator owns the remote and asked (`docs/git.md`).
- `GHOST_AUTO_PROMPT=1` is optional two-pass ASR from **this job’s** metadata; it does not create language lexicons.
- Do not send `frames/` to a vision model unless `MANIFEST.analyze_frames` is true or the operator asked. Source of truth is the job dir, not this skill.

## Phases

1. Mac: `./scripts/ingest.sh '<url>'`. CPU/CI: `docker compose run --rm ingest '<url>'`.
2. Open `jobs/<id>/MANIFEST.json`. If `status` is not `ok`, stop and report `pipeline.log`.
3. Read `transcript/canonical.en.txt` (+ frames only if `analyze_frames` is true). Write `analysis/context.md`, `meaning.md`, `intent.md` using `prompts/understand.md` (copied into the job).
4. Optional wiki file: `docs/gbrain.md`.

## Invoke

```bash
./scripts/bootstrap.sh --host
./scripts/ingest.sh smoke easy
./scripts/ingest.sh 'https://www.youtube.com/watch?v=VIDEO_ID'
```

Job dir is printed on success and always `jobs/<id>/`.

## Anti-patterns

- Summarizing from the watch page instead of `transcript/canonical.en.txt`
- Creating people pages from ASR spellings without a lookup
- Vision-token spend on `frames/` without `analyze_frames` or an explicit ask
