# Corresponding source

The binaries are unmodified copies of the archives in `manifest.json`.
Equivalent, no-charge source and build access is provided below. Preserve this
file and the adjacent license files with every redistribution.

## FFmpeg 8.1.2 Essentials

- [Binary archive](https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-8.1.2-essentials_build.zip)
  (`SHA-256 db580001caa24ac104c8cb856cd113a87b0a443f7bdf47d8c12b1d740584a2ec`)
- [Exact FFmpeg source](https://github.com/FFmpeg/FFmpeg/archive/38b88335f99e76ed89ff3c93f877fdefce736c13.zip)
- [Gyan build recipe and patches](https://github.com/GyanD/codexffmpeg/tree/8.1.2)
- `ffmpeg/README.upstream.txt` records the complete configure line and linked
  library versions.

## mpv 2026-07-26

- [Binary archive](https://github.com/zhongfly/mpv-winbuild/releases/download/2026-07-26-b27573a239/mpv-x86_64-20260726-git-b27573a239.7z)
  (`SHA-256 cee9077eb838c920ff1888e056cab79797539c97ed91e004bd1cf5a56afe19d5`)
- [Exact mpv source](https://github.com/mpv-player/mpv/archive/b27573a239b4da8fd8cf2bbc59d74a1a9b56a32b.zip)
- [Build recipe, dependency pins, and patches](https://github.com/zhongfly/mpv-winbuild/tree/2026-07-26-b27573a239)
- [Build log](https://github.com/zhongfly/mpv-winbuild/actions/runs/30199331587)
- [Embedded FFmpeg source](https://github.com/FFmpeg/FFmpeg/archive/601d9ee881fbd9d9ff44466c561c480ff244eb9f.zip)
- [Embedded libplacebo source](https://github.com/haasn/libplacebo/archive/4c426e466814536def653cb23f1d1c287ea7a7f5.zip);
  the executable reports this revision as `dirty`, so preserve the build
  recipe's applied patches with the source.

## MeCab and IPADIC

- [MeCab source archive](https://github.com/shogo82148/mecab/releases/download/v0.996.13/mecab-0.996.13.tar.gz)
  (`SHA-256 3da28541062d6d1cfbb92ab09481779f2ad735c89705d981eb66f072ef776538`)
- [IPADIC source archive](https://github.com/shogo82148/mecab/releases/download/v0.996.13/mecab-ipadic-2.7.0-20070801.tar.gz)
  (`SHA-256 74130f44264ce5b8cfa51e498b99345f71d2f854b74a9e9dfb6489e13e479e67`)

For each future binary update, archive the exact source, build scripts, patches,
configuration, and license texts beside the binary release; update all hashes.
The GPL components must remain available for as long as their object code is
offered. See the [FFmpeg legal checklist](https://ffmpeg.org/legal.html) and
[GPLv3 section 6](https://www.gnu.org/licenses/gpl-3.0.html#section6).
