# Outputs

Job directory: `jobs/<id>/` (or `$GHOST_JOBS/<id>/` in the container).

```
<id>/
  MANIFEST.json
  status.json
  pipeline.log
  source/
    audio.wav              # 16 kHz mono, always
    audio.*                # original bitstream
    video.*                # optional, ≤720p
    *.jpg                  # thumbnail
    *info.json             # yt-dlp
    yt-dlp-print.json
    captions/manual/<lang>.srt
    captions/auto/<lang>.srt
  frames/
    scene-0001.jpg         # cap 24
  transcript/
    transcript.txt
    transcript.srt
    whisper.json
    asr_status.json        # ok | skipped | empty | failed
    captions_status.json   # present, kind=manual|auto|none
    canonical.en.txt       # English of record for analysis
    canonical.json         # source: whisper_* | captions_* | unusable
  analysis/
    understand.md          # copied prompt
    README.md
    context.md             # agent
    meaning.md             # agent
    intent.md              # agent
```

## MANIFEST.json

```json
{
  "status": "ok",
  "url": "https://www.youtube.com/watch?v=…",
  "id": "…",
  "title": "…",
  "channel": "…",
  "duration": 1268,
  "upload_date": "20260717",
  "tools": { "ffmpeg": "…", "yt-dlp": "…", "whisper_model": "ggml-base.en.bin" },
  "asr": { "status": "ok", "model": "ggml-base.en.bin" },
  "frames": 12,
  "analyze_frames": false,
  "paths": { "audio": "source/audio.wav", "transcript": "transcript/transcript.txt" }
}
```

Paths in `paths` are relative to the job dir.
