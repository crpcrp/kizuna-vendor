#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "Linux x86_64 is required." >&2
  exit 1
fi

sha256sum --check SHA256SUMS.txt

executables=(
  linux-x64/mpv/bin/mpv
  linux-x64/ffmpeg/bin/ffmpeg
  linux-x64/ffmpeg/bin/ffprobe
  linux-x64/mecab/bin/mecab
  linux-x64/mecab/bin/mecab.bin
)
for executable in "${executables[@]}"; do
  test -x "$executable"
  file "$executable"
done

linux-x64/mpv/bin/mpv --version
linux-x64/ffmpeg/bin/ffmpeg -version
linux-x64/ffmpeg/bin/ffprobe -version
linux-x64/mecab/bin/mecab --version

printf '日本語を勉強します。\n' \
  | linux-x64/mecab/bin/mecab \
  | grep -F $'日本語\t名詞'

linux-x64/ffmpeg/bin/ffmpeg -hide_banner -encoders 2>/dev/null \
  | grep -F libmp3lame
linux-x64/mpv/bin/mpv --no-config --gpu-context=help 2>&1 \
  | grep -E 'x11egl|x11vk'
linux-x64/mpv/bin/mpv --no-config --list-options \
  | grep -F -- '--wid'

for executable in \
  linux-x64/mpv/bin/mpv \
  linux-x64/ffmpeg/bin/ffmpeg \
  linux-x64/ffmpeg/bin/ffprobe; do
  if ldd "$executable" | grep -F 'not found'; then
    echo "Missing shared-library dependency for $executable" >&2
    exit 1
  fi
  ldd "$executable"
done

LD_LIBRARY_PATH="$repo_root/linux-x64/mecab/lib" \
  ldd linux-x64/mecab/bin/mecab.bin

echo "Linux x64 payload verification passed."
