# ghost_media_ingest

Docker ingest for internet video. Agent judgment happens after `MANIFEST.json` exists.

- Pipeline: `docs/pipeline.md`
- Install: `INSTALL_FOR_AGENTS.md` (stop at smoke easy).
- Invoke (Mac): `./scripts/bootstrap.sh --host` then `./scripts/ingest.sh '<url>'` (Metal). Docker is CPU-only.
- Analysis: `prompts/understand.md` → `analysis/{context,meaning,intent}.md`
- Frame LLM/vision: off unless `MANIFEST.analyze_frames` is true (`GHOST_ANALYZE_FRAMES=1`) or the operator asked. ffmpeg stills on disk are not an invite to spend vision tokens.
- Wiki/GBrain: only if asked — `docs/gbrain.md`
- Never invent speech. This kit does not publish remotes (`docs/git.md`).
