# Understand this ingest

Harness-agnostic. Any agent filling `analysis/` for this job: read `MANIFEST.json`, `transcript/canonical.en.txt`, and `transcript/canonical.json`. Whisper-only text is `transcript/transcript.txt` (do not mix the two unmarked). Platform captions live under `source/captions/` with `transcript/captions_status.json`.

Do not invent speech. If `canonical.json` `source` is `unusable`, or the canonical file is `[transcript unavailable]` / `[transcript unusable]`, say so in each file and stop guessing quotes. Quote meaning.md from `canonical.en.txt` and cite `canonical.json` (whisper vs human captions vs auto captions).

**Frames:** ffmpeg may have written `frames/scene-*.jpg`. Do **not** open those images or send them to a vision model unless `MANIFEST.json` has `"analyze_frames": true` or the operator explicitly asked. Do not invent slides or lower-thirds if you did not analyze frames.

Write three files. Keep the layers separate.

## analysis/context.md

Who spoke, where, to whom, after what, duration, date. Channel and venue from MANIFEST / description — not from vibes. Use on-screen text from frames only if frame analysis is on.

## analysis/meaning.md

The argument, in the speaker's terms. Timestamped claims when the `.srt` exists. Label estimates as estimates.

## analysis/intent.md

What the speaker wants the audience to do. Infer from audience + ask + close. Quote the steal line / CTA if it is in the transcript.

Then, only if the operator asked to file this in a wiki, follow `docs/gbrain.md`.
