#!/usr/bin/env bash
# Install one host runtime at a time.
# usage: bootstrap-mac.sh mlx|faster|lightning|whisperkit
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WHICH=${1:?mlx|faster|lightning|whisperkit}

# mlx-whisper's tiktoken/pyo3 wheel SIGSEGV on CPython 3.14 (CoreBPE HashMap extract).
# Keep a dedicated 3.10–3.13 venv for mlx; other runtimes stay on .venv.
PY=python3
if [[ "$WHICH" == "mlx" ]]; then
  VENV=$ROOT/.venv-mlx
  if command -v python3.12 >/dev/null; then PY=python3.12
  elif command -v python3.13 >/dev/null; then PY=python3.13
  elif command -v python3.11 >/dev/null; then PY=python3.11
  fi
  ver=$($PY -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
  case "$ver" in
    3.1[0-3]) ;;
    *) echo "mlx needs CPython 3.10–3.13 (tiktoken crash on 3.14). Found $PY $ver" >&2; exit 1 ;;
  esac
else
  VENV=$ROOT/.venv
fi

"$PY" -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
python -m pip install -U pip

case "$WHICH" in
  mlx)        pip install mlx-whisper ;;
  faster)     pip install faster-whisper ;;
  lightning)  pip install lightning-whisper-mlx ;;
  whisperkit)
    command -v whisperkit-cli >/dev/null || brew install whisperkit-cli
    whisperkit-cli --help >/dev/null
    echo "whisperkit-cli $(command -v whisperkit-cli)"
    ;;
  *) echo "usage: bootstrap-mac.sh mlx|faster|lightning|whisperkit" >&2; exit 2 ;;
esac
echo "bootstrapped $WHICH"
