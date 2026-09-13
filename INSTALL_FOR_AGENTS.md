# INSTALL_FOR_AGENTS.md

Mutating. One-time. Binaries + smoke easy `MANIFEST.json`, then STOP.
This is not `SKILL.md`. This is not GBrain’s `INSTALL_FOR_AGENTS.md`. Do not ingest a URL. Do not write `analysis/`.

## Do not

- Invent speech. ffmpeg stills ≠ vision. Wiki / `git push` only if asked.
- Install GBrain, Graphify, or Graphiti from this file. Wiki filing is operator-gated (`docs/gbrain.md`) and is not install.
- Ingest `https`. Install Docker Desktop, Homebrew, mlx, or pip whisper.
- Add remotes. Commit `jobs/`, `models/`, `cookies.txt`, or lexicons (except `lexicons/example.txt`).

## Path

1. Darwin + `brew` → **A**. Docker on a Mac is CPU-only; do not prefer it.
2. Else `docker` and `docker compose version` → **B**.
3. Else **C**. STOP. Report missing. Do not improvise packages.

Linux/CI is **B** only. Windows / no brew / no compose → **C**.

## Path A (Mac host, Metal)

```bash
./scripts/bootstrap.sh --host
command -v ffmpeg yt-dlp jq whisper-cli
ffmpeg -hide_banner -hwaccels | grep -qx videotoolbox
./scripts/ingest.sh smoke easy
jq -e '.status=="ok"' jobs/_smoke/easy/out/easy/MANIFEST.json
```

`--host` installs Homebrew `ffmpeg` (must list `videotoolbox`), `whisper-cpp` (`whisper-cli`, Metal on by default), `yt-dlp`, `jq`. It does **not** build Docker, download ggml weights, or install Docker Desktop. `bootstrap.sh` does not call `ingest.sh` (separate steps).

## Path B (Docker CPU)

```bash
./scripts/bootstrap.sh
# docker compose build + smoke easy. Does not install Docker Desktop.
# requires the compose plugin (`docker compose version`), not v1 `docker-compose`.
```

Image: `ghost-media-ingest:local`. Volumes: `./jobs` → `/jobs`, `./models` → `/models`. No Metal, ANE, or VideoToolbox in the container. If Darwin and you are on **B**, say CPU-only.

## Done when

- Path **A** or **B** exit 0, and `jobs/_smoke/easy/out/easy/MANIFEST.json` has `.status=="ok"`.
- Easy smoke is local lavfi, no net, `GHOST_SKIP_ASR=1`. It does **not** prove Whisper.
- Report: `path=A|B`, ffmpeg/yt-dlp/whisper-cli versions (A) or image tag (B), job dir, `ready. No URL ingested.`
- Do not open `frames/`. Do not fill `analysis/`. Wait. Operator URL → `SKILL.md`.

## Not install

- `scripts/bootstrap-mac.sh` — optional ASR adapters. Not required. `docs/whisper-mac.md` is not an install menu.
- `GHOST_ANALYZE_FRAMES=1` — stamps `MANIFEST.analyze_frames`. Default analysis is transcript-only.
- Cookies, `GHOST_REFERER`, lexicons, `GHOST_AUTO_PROMPT` — ingest-time (`docs/pipeline.md`). Not install.
- `scripts/purge.sh` — not part of install.
- Weights — first **real** ingest downloads ggml into `models/` (gitignored). Host adapter default `ggml-small.en.bin`. Compose default `ggml-base.en.bin`. Easy smoke does not fetch them.

## Failures

Emit this and stop. Do not chain fallbacks the operator did not ask for.

```
INSTALL FAILED
path: A|B|C
missing: homebrew | videotoolbox | whisper-cli | docker | compose | smoke MANIFEST
did not: invent packages, ingest a URL, push git, file wiki, open frames
ask: <one question>
```

Allowed retry: `brew reinstall ffmpeg` once if videotoolbox is missing. Fail again → **C**, not silent Docker unless the operator asked for CPU.

`--host` needs Homebrew already on PATH. Path **B** needs Docker already installed. Missing either → **C**.

## After Gate A

Operator gives a URL or local file → `SKILL.md`. Judgment starts after that job’s `MANIFEST.json` exists. Gold text is `transcript/canonical.en.txt`. If ASR is not `ok`, say `[transcript unavailable]`. Do not summarize the watch page.

## Pointers

- Runtime ingest + analysis: `SKILL.md`
- Stages / env / failures: `docs/pipeline.md`
- CPU image: `docs/docker.md`
- Host Metal vs Docker CPU: `docs/whisper-mac.md`
- Remotes / what not to commit: `docs/git.md`
- Wiki only if asked: `docs/gbrain.md`
