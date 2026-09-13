<div align="center">
  <img src="assets/ghost-block.svg" width="240" alt="PixelGhost" />
  <br />
  <strong><a href="https://pixelghost.io">PixelGhost Studios</a></strong>
</div>

# PixelGhost Media-Brain Ingest Stack

Turn a YouTube, Vimeo, or other [yt-dlp](https://github.com/yt-dlp/yt-dlp) URL into a job directory another agent can read: audio, frames, transcript, then a prompt for context / meaning / intent.

On a Mac, decode + ASR are meant to run **on the host**: Homebrew ffmpeg and `whisper-cli` (**Metal GPU**). Docker cannot use Metal, ANE, or VideoToolbox. We do not re-encode video (no h264/h265 encode).

## Quickstart

```bash
cd ghost_media_ingest
./scripts/bootstrap.sh --host    # brew ffmpeg + whisper-cpp; also builds the CPU image
./scripts/ingest.sh 'https://www.youtube.com/watch?v=VIDEO_ID'
```

Portable/CI (CPU only):

```bash
./scripts/bootstrap.sh           # docker compose build + smoke easy
docker compose run --rm ingest 'https://www.youtube.com/watch?v=VIDEO_ID'
```

Output: `jobs/<id>/` — see [docs/outputs.md](docs/outputs.md). Wiki/GBrain filing is optional. Media purge: [docs/retention.md](docs/retention.md). Git: [docs/git.md](docs/git.md).

Then the agent fills `analysis/context.md`, `meaning.md`, `intent.md` ([prompts/understand.md](prompts/understand.md)).

| Path | ffmpeg | whisper-cli |
|---|---|---|
| **Host (Mac)** | Homebrew; VideoToolbox present, unused for encode | **Metal** (default) |
| **Docker** | Debian CPU | **CPU** (NEON/fp16) |

## Docs

| File | What |
|---|---|
| [docs/pipeline.md](docs/pipeline.md) | stages, env, failures |
| [docs/docker.md](docs/docker.md) | image, volumes, smoke |
| [docs/outputs.md](docs/outputs.md) | job tree + MANIFEST |
| [docs/gbrain.md](docs/gbrain.md) | optional wiki filing |
| [docs/git.md](docs/git.md) | remotes, what not to commit |
| [docs/retention.md](docs/retention.md) | keep text, drop media |
| [docs/whisper-mac.md](docs/whisper-mac.md) | host Metal vs Docker CPU |
| [THIRD_PARTY.md](THIRD_PARTY.md) | yt-dlp, FFmpeg, whisper.cpp, … |
| [SKILL.md](SKILL.md) | drop into an agent skill pack |

## Terms

You pass the URL. You are responsible for that site's terms and for rights to the media. This repo does not scrape accounts. Publication of **this** git remote is your choice ([docs/git.md](docs/git.md)).

## Layout

```
scripts/bootstrap.sh --host   # prereqs
scripts/ingest.sh             # URL → jobs/<id>/
scripts/purge.sh
Dockerfile                    # CPU fallback image
```

## License

This project is licensed under the [MIT License](LICENSE).

Copyright (c) 2026 PixelGhost Studios LLC.

Tools this kit **calls** (yt-dlp, FFmpeg, whisper.cpp, …) keep their own licenses — see [THIRD_PARTY.md](THIRD_PARTY.md). Keep those notices if you ship a built image.
