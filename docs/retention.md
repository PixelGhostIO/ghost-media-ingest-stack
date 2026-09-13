# Retention

Processing root is `jobs/<id>/` (`GHOST_JOBS`). This is not a knowledge base. Filing into a wiki/GBrain is a later operator choice (`docs/gbrain.md`). Purge never writes a wiki.

After **healthy ASR** (`transcript/asr_status.json` status `ok`):

| Keep | Drop (opt-in) |
|---|---|
| `MANIFEST.json`, `pipeline.log`, info.json, description, thumbnail | `source/video.*` |
| `transcript/transcript.txt`, `.srt`, `whisper.json`, `asr_status.json`, `auto-prompt.txt` | `source/audio.wav` and other audio bitstreams |
| `analysis/` (until the operator says otherwise) | `transcript/pass1/` |
| `frames/` (ffmpeg stills on disk; not an LLM step unless `analyze_frames`) | `frames/` only with `--drop-frames` |

Failed ASR: do not delete wav (needed to re-run).

```bash
GHOST_PURGE=1 docker compose run --rm ingest 'URL'   # drop media after this job
scripts/purge.sh                    # dry-run
scripts/purge.sh --apply --ttl 14
scripts/purge.sh --apply --include-smoke --include-bench
```

`--apply` is required to delete. Default is dry-run. `--keep-media` skips media deletes. Never deletes `analysis/` in v1. Cookies only with `--drop-cookies`.
