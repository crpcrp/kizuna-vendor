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
| `ppocr/` (Windows) | ONNX Runtime 1.24.4, PP-OCRv5 | Offline Japanese screen OCR |
| `linux-x64/mpv/` | Ubuntu mpv 0.37.0-1ubuntu4 | Media playback and X11 embedding |
| `linux-x64/ffmpeg/` | Ubuntu FFmpeg 6.1.1-3ubuntu5 | Media probing and conversion |
| `linux-x64/mecab/` | Ubuntu MeCab 0.996-14ubuntu4 | Tokenization with UTF-8 IPADIC |

## How Kizuna gets these files

Not by cloning this repository. Each release here carries one `.tar.gz` per
platform, and Kizuna's `npm run resources` downloads the one it needs, pinned by
tag, asset name, SHA-256, and byte length in its `resources.lock.json`.

Cloning meant `git lfs pull`, which fetches every LFS object at the commit —
both platforms, ~529 MB — on every build that missed its cache, against a
metered monthly bandwidth quota. A release asset is not metered, carries one
platform, and compresses to roughly a third of the size.

After changing any payload, publish the archives for the new commit by running
the **Publish payload archives** workflow (Actions > Run workflow). It packages
with a `GITHUB_TOKEN` scoped to this repository, records which commit produced
which asset hash, and puts the `source` block for Kizuna's
`resources.lock.json` on the run summary.

Publishing from a runner does cost LFS bandwidth, because a runner starts with
pointers and has to fetch the payload before it can package it. Only the
selected platform is fetched, and the two cost very differently:

| `--platform` | fetched per publish |
| --- | --- |
| `linux-x64` | 58 MB |
| `win32-x64` | 471 MB — ffmpeg 204, mpv 118, mecab 108, ppocr 41 |
| `all` | 529 MB |

`scripts/publish-payloads.sh` is that same code path and stays runnable
locally:

```bash
./scripts/publish-payloads.sh --platform linux-x64 --dry-run
./scripts/publish-payloads.sh --platform win32-x64
```

A local run fetches nothing — the objects are already in the working tree that
produced them — so publishing the Windows payload from the machine that built
it costs no LFS bandwidth at all. It is not a weaker provenance claim than the
workflow's, because the archive is reproducible: the same commit packaged
anywhere yields the same SHA-256, so a runner can confirm the published hash
without anyone trusting the laptop. What the workflow adds is a token scoped to
this repository instead of a personal login, and a permanent record of the run.

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
ppocr/bin/*                     -> resources/ppocr/
ppocr/models/                   -> resources/ppocr/models/
ppocr/licenses/                 -> notices for the packaged build
```

`ppocr/` is a Windows-only payload. Keep `ppocr.exe` and every DLL in one flat
directory; the worker resolves its own DLLs from there. Its JSON-lines protocol
is the contract implemented by Kizuna's `ppOcrWorker.ts`, which passes
`--det-model`, `--rec-model`, and `--keys` as three *file* paths — `det.onnx`,
`rec.onnx`, and `keys.txt` — not as model directories.

Nothing else has to be prepared at package time. `bin/` is the complete runtime
closure — everything it imports that is not in that directory is a Windows
system DLL — and `manifest.json` records a SHA-256 for every one of its files
plus every model file, so a truncated copy fails Kizuna's `resources.lock.json`
cross-check instead of shipping. OpenCV is statically linked, and only `core`,
`imgproc` and `imgcodecs` are built, so there is no Media Foundation
requirement and no host requirement beyond a 64-bit CPU.

`ppocr/worker/` and `ppocr/patches/` travel with the payload because `ppocr.exe`
is GPL-3.0-or-later and they are its corresponding source. They are not runtime
files and do not need to be staged into `resources/`, but whoever ships the
executable has to keep the source offer available.

PP-OCRv5 recognition covers Simplified Chinese, Traditional Chinese, English,
Japanese, and Pinyin in a single model; there is no Japanese-specific weight
file for this generation. Kizuna ships the mobile detector and the mobile
recognizer, chosen on measurement rather than size: across a 1920x1080 capture
rendered four ways the mobile pair read 19 of 20 Japanese lines against the
server recognizer's 15 of 20, and faster. `models/keys.txt` is the 18,383-entry
character dictionary, extracted from the recognizer's own metadata.

The worker loads and warms both models before its `ready` handshake and then
stays alive across captures, so model startup happens while Game OCR is armed
rather than after the capture shortcut. On the spike host it starts in about
0.5 s and answers the committed 1080p fixture in about 80 ms warm p50.

Unlike the other Windows components, this payload is built from source rather
than extracted from an upstream release. It is built and verified on a developer
machine and committed through Git LFS; no CI job builds or checks it, because
both need a Windows host that has already pulled the whole payload. The publish
workflow only repackages what was committed here, so nothing about this binary
is ever produced by GitHub. Rebuild it on a Windows x64 host with Visual Studio
2022 Build Tools and 7-Zip:

```powershell
./scripts/build-ppocr-onnx-win-x64.ps1
./scripts/refresh-ppocr-onnx-hashes.ps1
./scripts/verify-ppocr-onnx-win-x64.ps1
```

The build cache defaults to `C:\kizuna\build-tools\ppocr`; `-Clean` rebuilds
from the pinned sources without discarding the downloads. `ppocr/README.md`
records the worker contract, its tuning defaults, and the detection-side-length
measurements behind them.

Every payload that is built rather than mirrored keeps its build tree in its
own directory under `C:\kizuna\build-tools`, never in-tree and never scattered
across the drive. Nothing in there is committed: the repository holds the
finished payload plus the inputs a build cannot rederive, and the pinned URLs
and SHA-256 hashes inside each build script are what makes the tree
reproducible without it.

The build script verifies every downloaded archive before use — ONNX Runtime,
RapidOcrOnnx, the OpenCV source package, and both PP-OCRv5 ONNX models. It
applies the reviewed patches in `ppocr/patches/` to the vendored RapidOcrOnnx
tree, builds `ppocr/worker/ppocr_worker.cc` against it, and stages only the
runtime closure.

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
- RapidOcrOnnx, OpenCV, and the PP-OCRv5 weights and their ONNX conversion:
  Apache-2.0. ONNX Runtime: MIT. Clipper: BSL-1.0. zlib and libpng keep their
  own permissive terms, and the Microsoft runtime files use Microsoft's
  distributable-code terms. All texts are in `ppocr/licenses/`.
- Kizuna's persistent PP-OCR worker, and therefore the `ppocr.exe` it is linked
  into: GPL-3.0-or-later. The source is under `ppocr/worker/`, the reviewed
  RapidOcrOnnx modifications are under `ppocr/patches/`, and the license text is
  `ppocr/licenses/LICENSE.GPLv3.txt`. `ppocr/LICENSING.md` is the
  component-by-component record.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[CORRESPONDING_SOURCE.md](CORRESPONDING_SOURCE.md) before redistributing these
files. Review those records again whenever a binary changes.
