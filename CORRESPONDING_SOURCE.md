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

## PaddleOCR 3.7.0 (Windows OCR runtime)

Apache-2.0, MIT, BSD, and BSL-1.0 do not carry GPL's source-offer duty, but
this payload is compiled here rather than mirrored, so the full build inputs
are recorded and pinned in `scripts/build-paddleocr-win-x64.ps1`.

- [PaddleOCR 3.7.0 source](https://github.com/PaddlePaddle/PaddleOCR/archive/refs/tags/v3.7.0.tar.gz)
  (`SHA-256 8e5f1f9ba18c29621d38394b4f72925960640b315281391c3b3c86804f079a73`);
  only `deploy/cpp_infer` is built.
- [Paddle Inference 3.2.0 Windows CPU AVX MKL package](https://paddle-inference-lib.bj.bcebos.com/3.2.0/cxx_c/Windows/CPU/x86-64_avx-mkl-vs2019/paddle_inference.zip)
  (`SHA-256 23a2ea41abaedb7dfb928dc10baa72975d50b7a8ffe28f8e081a16a8977a95b2`),
  built from [Paddle `e22e2f9a`](https://github.com/PaddlePaddle/Paddle/tree/e22e2f9af7eeced7e3c9582ddb69a617887d3eb9)
- [OpenCV 4.10.0 Windows package](https://github.com/opencv/opencv/releases/download/4.10.0/opencv-4.10.0-windows.exe)
  (`SHA-256 bff38466091c313dac21a0b73eea8278316a89c1d434c6f0b10697e087670168`),
  built from [OpenCV 4.10.0](https://github.com/opencv/opencv/tree/4.10.0)
- [tronkko/dirent 1.24](https://github.com/tronkko/dirent/tree/1.24)
  (`SHA-256 7383044a375d481ac8ad7ec2f43151263eca792f085001a8020cc590114a06a6`
  for `include/dirent.h`)
- PaddleOCR's CMake dependencies are downloaded and verified before configure:
  Abseil (`SHA-256 ab51954baa519cb2c11fb461b0bdfd32836779ff3f3e50e5b845b0c80374ed6a`),
  Clipper 6.4.2 (`SHA-256 54ae753a24fcac5386416ea30ac1599cac60b00c27dab0d4f66696155b01e2be`),
  and nlohmann/json (`SHA-256 e04437150e0f302346e41501a2c6c918e87f57a4b605b8770601c9d8cf2b541a`).
- Toolchain: the installed MSVC v143 (Visual Studio 2022 Build Tools), CMake
  generator `Visual Studio 17 2022`, architecture x64, configuration Release,
  with `WITH_MKL=ON`, `WITH_GPU=OFF`, and `WITH_STATIC_LIB=ON`.

The build adds the `dirent.h` shim include directory and rewrites the `set(SRCS
cli.cc )` line in `deploy/cpp_infer/CMakeLists.txt` to `set(SRCS
kizuna_worker.cc )`, so PaddleOCR's source list uses the GPL-3.0-or-later
Kizuna worker entrypoint instead of its one-shot CLI. The CMake target keeps
its upstream `ppocr` name and the executable is renamed to `paddleocr.exe` when
it is staged, which lets the build directory stay incremental across reruns. The
worker constructs the pipeline configuration in memory, loads and warms the
models once, and serves Kizuna protocol v1 until standard input closes.
`mklml.dll` and `libiomp5md.dll` inside the Paddle Inference package are
byte-identical to Intel's
[`mklml_win_2019.0.5.20190502.zip`](https://paddlepaddledeps.bj.bcebos.com/mklml_win_2019.0.5.20190502.zip)
(`SHA-256 535857b17643d7f7546b58fc621244e7cfcc4fff2aa2ebd3fc5b4e126bfc36cf`),
and `opencv_world4100.dll` is byte-identical to the OpenCV package's copy;
both were checked when this payload was built. Repeat those checks whenever
the payload changes.

## PP-OCRv5 models

- [Detection `PP-OCRv5_mobile_det`](https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv5_mobile_det_infer.tar)
  (`SHA-256 50446e5d01ac2a73d5319c89513281f6578414c888c602f9af13f93feefffc58`)
- [Recognition `PP-OCRv5_mobile_rec`](https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv5_mobile_rec_infer.tar)
  (`SHA-256 566b9512b34e34a9f0db54d87b51fa5a0b9ed2cf1ab7e49728cc0b8b5a64f414`)
- Both are extracted unmodified into `models/det` and `models/rec`; their
  `inference.json`,
  `inference.pdiparams`, and `inference.yml` files match the archives.
- The all-mobile pair was chosen over the server recognizer on measurement, not
  on size: across four renderings of a 1920x1080 capture it read 19 of 20
  Japanese lines at 1.6-2.0 s per frame against the server recognizer's 15 of
  20 at 2.1-2.6 s.
- Model training recipes and configuration live with
  [PaddleOCR 3.7.0](https://github.com/PaddlePaddle/PaddleOCR/tree/v3.7.0).

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
