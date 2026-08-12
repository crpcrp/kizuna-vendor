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

## PP-OCR ONNX runtime (Windows x64)

`ppocr.exe` is conveyed under GPL-3.0-or-later. Its entry point is
`ppocr/worker/ppocr_worker.cc`; the exact RapidOcrOnnx modifications are in
`ppocr/patches/`; and `scripts/build-ppocr-onnx-win-x64.ps1` pins, verifies,
builds and stages every input.

- [RapidOcrOnnx `abd498c`](https://github.com/RapidAI/RapidOcrOnnx/tree/abd498c13a6dbe5f3b3c0d421d72e01bb3e6ee6d),
  archive SHA-256
  `059a5fb008dbc7d5d0e7606e73f23a649b86000f0ddc696051abd02aea56edab`.
- [Microsoft.ML.OnnxRuntime 1.24.4](https://www.nuget.org/packages/Microsoft.ML.OnnxRuntime/1.24.4),
  NuGet SHA-256
  `4b978d5065b85e7004b6c6f60ca494bd978fbe6836cbf0a0b52d82b61ab99638`.
- [OpenCV 4.14.0](https://github.com/opencv/opencv/tree/4.14.0), Windows
  source package SHA-256
  `5f266a8b73bed535962d7e861a6457e32a0dd5f463ad0a7cf8707a135469be63`.
  The build recipe selects static `core`, `imgproc` and `imgcodecs`, including
  its pinned zlib 1.3.2 and libpng 1.6.57 sources.
- [PP-OCRv5 detection model](https://www.modelscope.cn/models/RapidAI/RapidOCR/file/view/v3.9.2/onnx/PP-OCRv5/det/ch_PP-OCRv5_det_mobile.onnx),
  SHA-256 `4d97c44a20d30a81aad087d6a396b08f786c4635742afc391f6621f5c6ae78ae`.
- [PP-OCRv5 recognition model](https://www.modelscope.cn/models/RapidAI/RapidOCR/file/view/v3.9.2/onnx/PP-OCRv5/rec/ch_PP-OCRv5_rec_mobile.onnx),
  SHA-256 `5825fc7ebf84ae7a412be049820b4d86d77620f204a041697b0494669b1742c5`.
  `ppocr/models/keys.txt` is extracted from this model's `character` metadata;
  `ppocr/tools/extract-keys.py` records the reproducible extraction.
- The all-mobile pair is pinned over the server recognizer on measurement, not
  on size: across four renderings of a 1920x1080 capture the mobile pair read 19
  of 20 Japanese lines against the server recognizer's 15 of 20, and faster.
  Training recipes and configuration for both live with
  [PaddleOCR 3.7.0](https://github.com/PaddlePaddle/PaddleOCR/tree/v3.7.0).

RapidOcrOnnx is modified by `0001` for the official ONNX Runtime layout,
session safety and UTF-8 correctness, and by `0002` for batched recognition and
profiling. `ppocr/LICENSING.md` is the prominent Apache-2.0 §4(b) modification
notice. Preserve the worker, patches, build script, configuration, exact input
archives and licence texts for as long as the executable is offered.

For each future binary update, archive the exact source, build scripts, patches,
configuration, and license texts beside the binary release; update all hashes.
The GPL components must remain available for as long as their object code is
offered. See the [FFmpeg legal checklist](https://ffmpeg.org/legal.html) and
[GPLv3 section 6](https://www.gnu.org/licenses/gpl-3.0.html#section6).

## Linux x64 Ubuntu 24.04 payload

The Linux executables are unmodified extracts from Ubuntu 24.04 archive
packages. `scripts/refresh-linux-x64.sh` downloads the exact `.deb` files,
verifies their SHA-256 values, extracts them, and rebuilds the UTF-8 dictionary.
Ubuntu's source package pages provide the upstream source plus Debian/Ubuntu
patches and build rules used by Launchpad:

- mpv `0.37.0-1ubuntu4`: [Ubuntu source package](https://launchpad.net/ubuntu/+source/mpv/0.37.0-1ubuntu4).
  The upstream tarball SHA-256 is
  `304da2bbb1303d6006b816c4f44de3a79f2a62a7bd7e90bca090116dafd2655c`;
  the Ubuntu patch archive SHA-256 is
  `997ce33f0fb476eea150207b8707b3dce42ca79abffdf166ca7af53d7d816a7b`.
- FFmpeg `7:6.1.1-3ubuntu5`: [Ubuntu source package](https://launchpad.net/ubuntu/+source/ffmpeg/7%3A6.1.1-3ubuntu5).
  The upstream tarball SHA-256 is
  `8684f4b00f94b85461884c3719382f1261f0d9eb3d59640a1f4ac0873616f968`;
  the Ubuntu patch archive SHA-256 is
  `874b7862a84e2afa89a74b9c736e988858becb8f17c0b0e8f339a71cb2ddbff1`.
- MeCab `0.996-14ubuntu4`: [Ubuntu source package](https://launchpad.net/ubuntu/+source/mecab/0.996-14ubuntu4).
  The upstream tarball SHA-256 is
  `e073325783135b72e666145c781bb48fada583d5224fb2490fb6c1403ba69c59`;
  the Ubuntu patch archive SHA-256 is
  `43c98fe565ffd8b4bc7294db26bb0fe25c40ace537918a713c32510f5941bc78`.
- IPADIC `2.7.0-20070801+main-3`: [Ubuntu source package](https://launchpad.net/ubuntu/+source/mecab-ipadic/2.7.0-20070801%2Bmain-3).
  The source tarball SHA-256 is
  `b62f527d881c504576baed9c6ef6561554658b175ce6ae0096a60307e49e3523`;
  the Debian patch archive SHA-256 is
  `2796c8e31f52d11c1393c53cd664756f83d609597123c50f658938449499993b`.

The dictionary recipe matches `mecab-ipadic-utf8`'s maintainer script:
`mecab-dict-index -f EUC-JP -t UTF-8`, using the pinned `mecab-utils` binary.
The complete archive hash set is embedded in the rebuild script and manifest.
