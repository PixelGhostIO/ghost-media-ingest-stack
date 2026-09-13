# Whisper on Apple Silicon

On a Mac, ASR should use **host** Homebrew `whisper-cli` (**Metal**). Docker `whisper-cli` is CPU-only and cannot see the Mac GPU.

On **Apple Silicon**: host `whisper-cli` loads Metal plus a CPU backend. `--no-gpu` forces CPU. The **Docker image is `linux/arm64` or `linux/amd64`**: no Metal (ARM CPU / x86 only).

Host ffmpeg (Homebrew) is built with VideoToolbox. This kit does **not** re-encode h264/h265, so the VT **encoder** is unused. Audio-to-wav and JPEG stills do not need VT.

Example bake-off, **small.en / small**, ~8 s TTS clip (`fixtures/gold.txt`), weights already on disk. Run your own numbers; hardware differs.

| # | Runtime | Backend | Notes |
|---|---|---|---|
| 1 | **whisper.cpp** `whisper-cli` | ggml Metal on host; CPU in Docker | Default. txt+srt+json. |
| 2 | **mlx-whisper** | MLX Metal | Fast Python path. Apple Silicon only. |
| 3 | **WhisperKit** | Core ML / ANE | Lowest RAM in one local run; CLI startup can dominate short clips. macOS only. |
| 4 | **faster-whisper** | CTranslate2 CPU int8 | Portable; CPU-only on Mac. Fine in Linux Docker. |
| 5 | **lightning-whisper-mlx** | MLX (2024) | Do not use: last PyPI 2024, segfaults on current mlx. |

Cold starts (first model fetch) are not a fair speed ranking.

```bash
scripts/bootstrap-mac.sh mlx          # one runtime at a time
scripts/asr/whisper_cpp.sh fixtures/gold.wav /tmp/out
scripts/asr/bakeoff.sh easy           # local numbers land in gitignored work/_bakeoff/
```

`GHOST_ASR=whisper_cpp` by default. Override: `mlx_whisper`, `whisperkit`, `faster_whisper`.

`scripts/bootstrap-mac.sh mlx` installs into `.venv-mlx` on CPython 3.12 (Homebrew `python3` is 3.14). mlx-whisper’s tiktoken/pyo3 wheel SIGSEGVs on 3.14 while loading the BPE tokenizer.

Non-English jobs fetch platform captions (YouTube/Vimeo/TikTok via yt-dlp) as **compare**, and as **fallback** when Whisper translate is unusable (Hindi-class). Default ASR is unchanged.

Gold-clip WER is a **runtime smoke**, not a dialect gate. Domain terms belong in an operator-supplied `--prompt` (`GHOST_WHISPER_PROMPT` or `GHOST_LEXICON=<name>` → `lexicons/<name>.txt`). Do not commit personal or regional lists. `lexicons/example.txt` is dummy proper nouns.

Optional two-pass (`GHOST_AUTO_PROMPT=1`): harvest title/tags/description/transcript into `transcript/auto-prompt.txt` and decode again. It does not detect language or invent a lexicon.

## Citations

- ggml-org/whisper.cpp, SYSTRAN/faster-whisper, mlx-whisper, Homebrew whisperkit-cli
