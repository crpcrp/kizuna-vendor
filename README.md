# Kizuna vendor runtime

Pinned Windows and Linux x64 runtime files for the Kizuna desktop application.
The binary provenance, versions, architectures, hashes, and source recipes are
recorded in [manifest.json](manifest.json).

## Contents

| Payload | Version | Purpose |
| --- | --- | --- |
| `mpv/` (Windows) | 0.41.0-906-gb27573a23 | Media playback |
| `ffmpeg/` (Windows) | 8.1.2 Essentials | Media probing and conversion |
| `mecab/` (Windows) | 0.996.13 | Japanese tokenization |
| `paddleocr/` (Windows) | PaddleOCR 3.7.0, PP-OCRv5 | Offline Japanese screen OCR |
| `linux-x64/mpv/` | Ubuntu mpv 0.37.0-1ubuntu4 | Media playback and X11 embedding |
| `linux-x64/ffmpeg/` | Ubuntu FFmpeg 6.1.1-3ubuntu5 | Media probing and conversion |
| `linux-x64/mecab/` | Ubuntu MeCab 0.996-14ubuntu4 | Tokenization with UTF-8 IPADIC |

Large files use Git LFS. Install Git LFS before cloning:

```powershell
git lfs install
git clone https://github.com/crpcrp/kizuna-vendor.git
```

Kizuna's Windows packaging step should copy the component folders into these
runtime locations:

```text
mpv/bin/mpv.exe                 -> resources/mpv/mpv.exe
ffmpeg/bin/*.exe                -> resources/ffmpeg/
mecab/bin/* + mecab/etc/mecabrc -> resources/mecab/
mecab/ipadic/                   -> resources/mecab/ipadic/
paddleocr/bin/*                 -> resources/paddleocr/
paddleocr/models/               -> resources/paddleocr/models/
```

`paddleocr/` is a Windows-only payload. Keep `ppocr.exe` and every DLL in one
flat directory; the worker resolves its own DLLs from there. `models/` holds
the PP-OCRv5 detection and recognition pair, selected by explicit
`--text_detection_model_dir` and `--text_recognition_model_dir` arguments, so
its location is free as long as both directories survive together.

PP-OCRv5 recognition covers Simplified Chinese, Traditional Chinese, English,
Japanese, and Pinyin in a single model; there is no Japanese-specific weight
file for this generation and no separate character dictionary, because the
PIR-format models embed it. Only the `mobile` pair is mirrored. The heavier
`server` pair, which `deploy/cpp_infer` picks by default for `lang=japan`,
scores about the same on game-style Japanese text while being eight times
larger, so `manifest.json` records its hashes without mirroring it.

Unlike the other Windows components, this payload is built from source rather
than extracted from an upstream release. Rebuild it on a Windows x64 host with
Visual Studio 2022 Build Tools and 7-Zip, then verify it:

```powershell
./scripts/build-paddleocr-win-x64.ps1
git lfs pull
./scripts/verify-paddleocr-win-x64.ps1
```

The build script verifies every downloaded archive before use and pins the
exact PaddleOCR tag, Paddle Inference build, OpenCV package, and model
archives. PaddleOCR 3.7.0 does not compile under MSVC unmodified: its
`src/utils/utility.cc` includes the POSIX `<dirent.h>`. The script supplies a
header-only MIT shim on the include path and edits no PaddleOCR source.

Two runtime notes worth carrying into packaging:

- `ppocr.exe` is a one-shot CLI. It loads both models, recognizes one image,
  prints JSON, and exits, costing roughly 1.5 s per run on an 8-core desktop.
  Anything wanting warm-process latency must link `deploy/cpp_infer`'s API
  instead of spawning this executable per capture.
- PaddleOCR gates oneDNN acceleration on an Intel CPU brand string
  (`Utility::IsMkldnnAvailable`), so AMD hosts silently fall back to the plain
  CPU backend. `mkldnn.dll` still ships because Intel hosts do use it.

For Linux, copy the complete component directories without renaming files:

```text
linux-x64/mpv/                  -> resources/mpv/
linux-x64/ffmpeg/               -> resources/ffmpeg/
linux-x64/mecab/                -> resources/mecab/
```

The Linux baseline is Ubuntu 24.04 LTS x86-64 with glibc 2.39. Linux packages
must declare the exact Ubuntu `mpv (= 0.37.0-1ubuntu4)` and
`ffmpeg (= 7:6.1.1-3ubuntu5)` packages as dependencies; their shared libraries
are intentionally supplied by the distribution. MeCab's non-baseline
`libmecab.so.2` travels in this mirror and its wrapper sets a relative loader
path. See [LINUX_X64_DEPENDENCIES.md](LINUX_X64_DEPENDENCIES.md) for the full
dependency audit and packaging policy.

Rebuild the Linux payload on a clean Ubuntu 24.04 x64 host, then verify it:

```bash
./scripts/refresh-linux-x64.sh
git lfs pull
./scripts/verify-linux-x64.sh
```

The rebuild script verifies every downloaded Ubuntu archive before extraction
and recompiles IPADIC as UTF-8. Git records mode `100755` for all five Linux
executables and both scripts; a fresh checkout must preserve those modes.

`SHA256SUMS.txt` records every redistributed payload file. `manifest.json`
records the exact binary archives, source commits, build recipes, licenses, and
key file hashes.

## Licensing

This repository has no single umbrella license. Each component remains under
its upstream terms:

- mpv build: GPL-3.0-or-later as distributed here.
- FFmpeg/ffprobe build: GPL-3.0-or-later.
- MeCab: redistributed under its BSD 3-clause option.
- IPADIC: its NAIST/ICOT license in `mecab/ipadic/COPYING`.
- PaddleOCR, Paddle Inference, oneDNN, OpenCV, and Abseil: Apache-2.0.
  Clipper: BSL-1.0. The statically linked helpers are BSD or MIT. The bundled
  Intel MKL small libraries use the Intel Simplified Software License, and the
  Microsoft runtime files use Microsoft's distributable-code terms. All texts
  are in `paddleocr/licenses/`.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[CORRESPONDING_SOURCE.md](CORRESPONDING_SOURCE.md) before redistributing these
files. Review those records again whenever a binary changes.
