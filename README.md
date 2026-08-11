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

Publish the archives for the current commit after changing any payload:

```bash
./scripts/publish-payloads.sh                     # both platforms
./scripts/publish-payloads.sh --platform linux-x64 --dry-run
```

The script re-verifies every file against `SHA256SUMS.txt`, refuses to package
an unresolved LFS pointer or an uncommitted tree, builds reproducible archives,
creates the release, and prints the `source` block to paste into Kizuna's
`resources.lock.json`. It needs the payload present on disk, so run it from a
full checkout on a machine that has pulled LFS at least once.

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
```

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

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[CORRESPONDING_SOURCE.md](CORRESPONDING_SOURCE.md) before redistributing these
files. Review those records again whenever a binary changes.
