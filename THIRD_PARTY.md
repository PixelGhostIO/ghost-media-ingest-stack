# Third-party software

This repository’s own source is MIT (PixelGhost Studios LLC). It **calls** other open-source programs. Those keep their own licenses. We do not relicense them.

| Component | Used for | License (upstream) |
|---|---|---|
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | Fetch audio/video/metadata | Unlicense |
| [FFmpeg](https://ffmpeg.org/) | Resample, frames | LGPL/GPL as provided by the distro or Homebrew build |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) / ggml | ASR (`whisper-cli`) | MIT |
| Debian bookworm-slim | Docker base | Debian terms |
| Python 3 | `auto_prompt.py` | PSF |

Optional host adapters (not required to run the image):

| Component | License (upstream) |
|---|---|
| [mlx-whisper](https://github.com/ml-explore/mlx-examples) / MLX | MIT |
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | MIT |
| [faster-whisper](https://github.com/SYSTRAN/faster-whisper) / CTranslate2 | MIT |

The Docker image installs distro FFmpeg and builds whisper.cpp from source. Redistributing a **built image** must follow those packages’ licenses (FFmpeg is often GPL when built with default Debian flags). This git tree is scripts + a Dockerfile, not a redistributed binary of FFmpeg.
