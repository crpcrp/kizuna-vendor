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

## How Kizuna gets these files

Not by cloning this repository. Each release here carries one `.tar.gz` per
platform, and Kizuna's `npm run resources` downloads the one it needs, pinned by
tag, asset name, SHA-256, and byte length in its `resources.lock.json`.

Cloning meant `git lfs pull`, which fetches every LFS object at the commit —
both platforms, ~855 MB — on every build that missed its cache, against a
metered monthly bandwidth quota. A release asset is not metered, carries one
platform, and compresses to roughly a third of the size.

After changing any payload, publish the archives for the new commit by running
the **Publish payload archives** workflow (Actions > Run workflow). It packages
with a `GITHUB_TOKEN` scoped to this repository, records which commit produced
which asset hash, and puts the `source` block for Kizuna's
`resources.lock.json` on the run summary.

`scripts/publish-payloads.sh` is that same code path and stays runnable
locally, mainly for a dry run:

```bash
./scripts/publish-payloads.sh --platform linux-x64 --dry-run
```

Either way it re-verifies every file against `SHA256SUMS.txt`, refuses to
package an unresolved LFS pointer or an uncommitted tree, and builds
reproducible archives — `tar` is invoked so the result is a pure function of
the tree, which means republishing a commit yields the same SHA-256 and a
deleted release can be restored without invalidating any lock that pinned it.

An asset that already exists is never silently overwritten, because something
may already have pinned its hash; replacing one takes `--replace`.

Large files still use Git LFS *inside* this repository, which only affects
people working on the payloads themselves:

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

`paddleocr/` is a Windows-only payload. Keep `paddleocr.exe` and every DLL in
one flat directory; the worker resolves its own DLLs from there. Its JSON-lines
protocol is the contract implemented by Kizuna's `paddleWorker.ts`. The
`models/det` and `models/rec` directories match Kizuna's resource paths.

PP-OCRv5 recognition covers Simplified Chinese, Traditional Chinese, English,
Japanese, and Pinyin in a single model; there is no Japanese-specific weight
file for this generation and no separate character dictionary, because the
PIR-format models embed it. Kizuna ships the mobile detector and the mobile
recognizer. The server recognizer was measured against it on a 1920x1080
capture rendered four ways: the mobile pair read 19 of 20 Japanese lines at
1.6-2.0 s per frame, the server recognizer 15 of 20 at 2.1-2.6 s. It is both
the faster and the more accurate choice here, so there is no tradeoff to
balance.

On a sixteen-core desktop the worker starts in about 0.6 s and then answers a
full-screen 1080p capture in about 1.5 s. Detection is a flat ~0.5 s and
recognition costs roughly 0.2 s per detected line, so latency tracks how much
text is on screen rather than the screen's resolution.

Unlike the other Windows components, this payload is built from source rather
than extracted from an upstream release. It is built and verified on a developer
machine and committed through Git LFS; no CI job builds or checks it, because
both need a Windows host that has already pulled the whole payload. Rebuild it
on a Windows x64 host with Visual Studio 2022 Build Tools and 7-Zip:

```powershell
./scripts/build-paddleocr-win-x64.ps1
./scripts/verify-paddleocr-win-x64.ps1
```

The build script caches its ~1.4 GB of dependencies under `C:\kzb`, so the
first run takes roughly ten minutes and later runs that only change
`paddleocr/worker/paddleocr_worker.cc` finish in well under a minute. It
refreshes `SHA256SUMS.txt` and `manifest.json` itself. Pass `-Clean` to rebuild
from scratch after changing a pinned version.

The build script verifies every downloaded archive before use, including the
three archives PaddleOCR's CMake normally fetches at configure time. It builds
`paddleocr/worker/paddleocr_worker.cc` against `deploy/cpp_infer` and applies
the recorded CMake patch. A header-only MIT `dirent.h` shim is also required
because MSVC does not provide PaddleOCR's POSIX header.

Two runtime notes worth carrying into packaging:

- `paddleocr.exe` loads and warms both models before its `ready` handshake,
  then stays alive across captures. Model startup therefore happens while
  Game OCR is armed, not after the capture shortcut. The verifier sends four
  requests through the real protocol and requires the median of the last three
  to finish within 2.5 s.
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
- Kizuna's persistent PaddleOCR worker: GPL-3.0-or-later; the source is under
  `paddleocr/worker/` and the license text is `mpv/LICENSE.GPLv3.txt`.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[CORRESPONDING_SOURCE.md](CORRESPONDING_SOURCE.md) before redistributing these
files. Review those records again whenever a binary changes.
