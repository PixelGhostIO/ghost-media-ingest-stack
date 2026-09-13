FROM debian:bookworm-slim

ARG TARGETARCH
ARG WHISPER_VERSION=v1.9.2

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        cmake \
        curl \
        ffmpeg \
        g++ \
        git \
        jq \
        make \
    && rm -rf /var/lib/apt/lists/*

RUN case "${TARGETARCH}" in \
      amd64) YT=yt-dlp_linux ;; \
      arm64) YT=yt-dlp_linux_aarch64 ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL "https://github.com/yt-dlp/yt-dlp/releases/latest/download/${YT}" \
         -o /usr/local/bin/yt-dlp \
    && chmod +x /usr/local/bin/yt-dlp \
    && yt-dlp --version

WORKDIR /tmp
# aarch64 Debian needs explicit +fp16; GGML_NATIVE=ON mis-detects in Docker.
RUN curl -fsSL "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/${WHISPER_VERSION}.tar.gz" \
      | tar xz \
    && src=$(echo /tmp/whisper.cpp-*) \
    && if [ "${TARGETARCH}" = "arm64" ]; then \
         extra="-DGGML_NATIVE=OFF -DCMAKE_C_FLAGS=-march=armv8.2-a+fp16 -DCMAKE_CXX_FLAGS=-march=armv8.2-a+fp16"; \
       else \
         extra="-DGGML_NATIVE=OFF"; \
       fi \
    && cmake -B /tmp/wbuild -S "$src" -DCMAKE_BUILD_TYPE=Release -DWHISPER_BUILD_TESTS=OFF $extra \
    && cmake --build /tmp/wbuild -j"$(nproc)" --target whisper-cli \
    && cp /tmp/wbuild/bin/whisper-cli /usr/local/bin/whisper-cli \
    && cp -a /tmp/wbuild/bin/*.so* /usr/local/lib/ \
    && ldconfig \
    && rm -rf /tmp/wbuild /tmp/whisper.cpp-* \
    && whisper-cli --help >/dev/null

RUN apt-get update && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY scripts /app/scripts
COPY prompts /app/prompts
RUN chmod +x /app/scripts/*.sh /app/scripts/asr/*.sh /app/scripts/asr/*.py

ENV GHOST_JOBS=/jobs \
    GHOST_WORK=/jobs \
    GHOST_MODELS=/models \
    GHOST_WHISPER_MODEL=ggml-base.en.bin

WORKDIR /jobs
ENTRYPOINT ["/app/scripts/ingest.sh"]
