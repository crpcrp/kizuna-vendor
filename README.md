# Kizuna vendor runtime

Pinned Windows x64 runtime files for the Kizuna desktop application. The files
are redistributed unmodified from the upstream archives identified in
[manifest.json](manifest.json).

## Contents

| Folder | Version | Purpose |
| --- | --- | --- |
| `mpv/` | 0.41.0-906-gb27573a23 | Media playback |
| `ffmpeg/` | 8.1.2 Essentials | Media probing and conversion |
| `mecab/` | 0.996.13 | Japanese tokenization |
| `mecab/ipadic/` | 2.7.0-20070801 | MeCab Japanese dictionary |

Large files use Git LFS. Install Git LFS before cloning:

```powershell
git lfs install
git clone https://github.com/crpcrp/kizuna-vendor.git
```

Kizuna's packaging step should copy the component folders into these runtime
locations:

```text
mpv/bin/mpv.exe                 -> resources/mpv/mpv.exe
ffmpeg/bin/*.exe                -> resources/ffmpeg/
mecab/bin/* + mecab/etc/mecabrc -> resources/mecab/
mecab/ipadic/                   -> resources/mecab/ipadic/
```

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
