# Pipeline

Source of truth for stages. README and SKILL.md point here.

Container work is deterministic. The agent does not live in Docker.

## Stages

| # | Name | Tool | Output |
|---|---|---|---|
| 1 | resolve | yt-dlp `--skip-download --print` | `source/yt-dlp-print.json`, job dir `jobs/<id>/` |
| 2 | fetch | yt-dlp | audio bitstream, optional `video.*` (≤720p), info.json, description, thumbnail |
| 3 | captions | yt-dlp `--write-subs` / `--write-auto-subs` (fail-open) | `source/captions/{manual,auto}/<lang>.srt`, `transcript/captions_status.json`. Skipped for local files. |
| 4 | audio | ffmpeg | `source/audio.wav` — 16 kHz mono |
| 5 | frames | ffmpeg | up to 24 `frames/scene-*.jpg` (scene 0.30, else `fps=1`, else first frame) |
| 6 | asr | whisper-cli | `transcript/transcript.txt`, `.srt`, `whisper.json`, `asr_status.json`. If `GHOST_AUTO_PROMPT=1`, second decode using `transcript/auto-prompt.txt` |
| 7 | canonical | `scripts/asr/canonical.py` | `transcript/canonical.en.txt` + `canonical.json`. Whisper stays canonical unless unusable (then human EN captions, then auto EN). |
| 8 | manifest | jq | `MANIFEST.json` |
| 9 | stop | cp | `analysis/understand.md` — no LLM in the container |

`pipeline.log` has one `STAGE <name>` line per stage.

## Inputs

```
docker compose run --rm ingest '<url-or-file>'
```

| Env | Default | Meaning |
|---|---|---|
| `GHOST_JOBS` | `jobs` (host) / `/jobs` (container) | processing root; job dir `jobs/<id>/`. `GHOST_WORK` is a deprecated alias. |
| `GHOST_MODELS` | `/models` | Whisper ggml files |
| `GHOST_WHISPER_MODEL` | `ggml-base.en.bin` | downloaded on first use |
| `GHOST_NO_FRAMES` | `0` | `1` skips video fetch + ffmpeg stills |
| `GHOST_ANALYZE_FRAMES` | `0` | `1` stamps `MANIFEST.analyze_frames: true`. Default analysis is transcript-only; vision/LLM on stills is opt-in. |
| `GHOST_SKIP_ASR` | `0` | `1` skips Whisper |
| `GHOST_COOKIES` | — | Netscape cookies; or `jobs/cookies.txt` |
| `GHOST_REFERER` | — | `--referer` for embed-only players (prefer the embedding page URL) |
| `GHOST_FORCE_GENERIC` | `0` | `1` → `--ies generic,default` (escape hatch, not default) |
| `GHOST_PLAYLIST_ITEMS` | `1` | `--playlist-items` (one embed per job) |
| `GHOST_VIDEO_PASSWORD` | — | `--video-password` if set |
| `GHOST_PURGE` | `0` | `1` = after healthy ASR, drop bulky media; keep transcript/analysis |
| `GHOST_WHISPER_PROMPT` | — | whisper-cli `--prompt` text, or a file path |
| `GHOST_WHISPER_LANG` | `en` | ASR spoken language (`auto` = detect). Host adapters only. |
| `GHOST_WHISPER_TASK` | `transcribe` | `transcribe` or `translate` (to English). Host adapters only. |
| `GHOST_LEXICON` | — | basename → `lexicons/<name>.txt` (initial prompt, not a second engine). No built-in lexicons besides `example`. |
| `GHOST_AUTO_PROMPT` | `0` | `1` = after first ASR, harvest title/tags/description/transcript into `transcript/auto-prompt.txt` and decode **again**. Off by default. Does not detect language or ship regional lists. |
| `GHOST_AUTO_PROMPT_MAX` | `32` | max terms in the auto prompt |
| `GHOST_SKIP_CAPTIONS` | `0` | `1` skips platform subtitle fetch |
| `GHOST_SUB_LANGS` | `all,-live_chat` | yt-dlp `--sub-langs` |
| `GHOST_YT_PLAYER_CLIENT` | `web,default` | YouTube caption client (web actually returns timedtext) |
| `GHOST_SUB_SKIP_TRANSLATED` | `1` | skip YouTube machine-translated caption tracks |
| `GHOST_SKIP_ASR_IF_MANUAL_EN` | `0` | `1` skips Whisper when human English captions exist |

Local files are allowed (smoke easy uses this).

## Failures

- resolve/fetch/audio/whisper non-zero → exit 1, `status.json` `{status:failed,stage,error}`
- empty ASR → write `[transcript unavailable]` and `asr_status=empty`; do not invent lines
- video fetch fail → warn, continue without frames
- **Never** fabricate transcript text

## Limits

- Single-speaker default. No diarization. Multi-speaker jobs: say so in analysis, do not invent names.
- YouTube auto-ASR captions mangle proper nouns — COMPARE only unless Whisper is unusable. Human EN captions may become `canonical.en.txt` on Hindi-class / empty / truncated Whisper. Never treat auto captions as gold. TikTok often has no tracks (fail-open).
- Operator is responsible for the URL (site terms, rights). This kit does not upload anywhere.
- Any yt-dlp URL (YouTube, Vimeo, many others). For embedded players, pass the **page that embeds** the video, or set `GHOST_REFERER`. DRM and login-only are not promised. See [retention.md](retention.md) for media cleanup.
