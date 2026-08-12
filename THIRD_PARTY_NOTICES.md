# Third-party notices

These notices cover the Windows and Linux x64 vendor files in this repository.
They do not license Kizuna's own source code.

## mpv

- Build: `0.41.0-906-gb27573a23`, Zhongfly regular x86_64 release
  `2026-07-26-b27573a239`.
- Copyright and per-file licensing: `mpv/Copyright`.
- mpv source is GPL-2.0-or-later by default. This static build includes
  GPL/version-3 components, so the distributed executable is treated as
  GPL-3.0-or-later.
- License texts: `mpv/LICENSE.GPLv2-or-later.txt` and
  `mpv/LICENSE.GPLv3.txt`.

## FFmpeg and ffprobe

- Build: Gyan FFmpeg `8.1.2-essentials_build-www.gyan.dev`, dated
  2026-06-27.
- The static build configuration includes `--enable-gpl --enable-version3`;
  Gyan identifies all regular builds as GPLv3.
- License: GPL-3.0-or-later.
- License text: `ffmpeg/LICENSE.GPLv3.txt`.
- Exact configuration and linked component versions:
  `ffmpeg/README.upstream.txt`.

## MeCab

- Build: `mecab-msvc-x64-0.996.13.zip`.
- Copyright © 2001-2008 Taku Kudo; © 2004-2008 Nippon Telegraph and
  Telephone Corporation.
- MeCab offers GPL, LGPL, and BSD terms. This redistribution selects the BSD
  3-clause option.
- Required copyright, conditions, and disclaimer:
  `mecab/LICENSE.BSD.txt`. Authors are recorded in `mecab/AUTHORS`.

## IPADIC

- Version: `2.7.0-20070801`, distributed with the matched MeCab package.
- Copyright © 2000-2003 Nara Institute of Science and Technology.
- Dictionary entries also contain ICOT Free Software material.
- The required copyright, redistribution terms, and no-warranty paragraphs
  accompany the dictionary in `mecab/ipadic/COPYING`.

## PP-OCR ONNX runtime

- `ppocr.exe` combines Kizuna's GPL-3.0-or-later protocol-v1 worker with a
  modified RapidOcrOnnx `abd498c` pipeline, OpenCV 4.14.0, Clipper 6.4.2,
  zlib 1.3.2 and libpng 1.6.57. The combined executable is conveyed under
  GPL-3.0-or-later; its corresponding source, exact patches and build recipe
  are kept under `ppocr/worker/`, `ppocr/patches/` and
  `scripts/build-ppocr-onnx-win-x64.ps1`.
- RapidOcrOnnx is Apache-2.0 and modified. The prominent modification notice is
  in `ppocr/LICENSING.md`; the patches adapt the official ONNX Runtime include
  layout, harden session and UTF-8 handling, and add batched fixed-width
  recognition and profiling hooks. Upstream ships no `NOTICE` file.
- OpenCV `core`, `imgproc` and `imgcodecs` are built from the pinned unmodified
  4.14.0 source and statically linked with zlib and libpng. Clipper is vendored
  by RapidOcrOnnx and statically linked under BSL-1.0.
- `onnxruntime.dll` and `onnxruntime_providers_shared.dll` are the CPU binaries
  from Microsoft.ML.OnnxRuntime 1.24.4 and remain separate MIT-licensed works.
  Microsoft's complete notices accompany them at
  `ppocr/bin/THIRD-PARTY-NOTICES.ONNXRuntime.txt`.
- `det.onnx`, `rec.onnx` and `keys.txt` are PP-OCRv5 weights, an ONNX
  conversion and its embedded dictionary from RapidAI's ModelScope mirror at
  revision `v3.9.2`. The underlying weights are Copyright © PaddlePaddle
  Authors and both the weights and conversion are Apache-2.0
  (`ppocr/licenses/LICENSE.PaddleOCR.txt`).
- PP-OCRv5 recognition handles Simplified Chinese, Traditional Chinese,
  English, Japanese, and Pinyin in one model. Kizuna uses it for Japanese; the
  other scripts are an inseparable property of the weights, not an added
  language payload.
- The worker uses the static MSVC runtime. Microsoft's prebuilt ONNX Runtime
  imports `msvcp140.dll`, `msvcp140_1.dll`, `vcruntime140.dll` and
  `vcruntime140_1.dll`, so those redistributable files accompany it under
  Microsoft's Distributable Code terms. No Intel MKL component is present.
- The exact licence and copyright texts accompany the payload under
  `ppocr/licenses/`; `ppocr/LICENSING.md` records the component-by-component
  analysis and Apache-2.0 modification notice.

The software is supplied without warranty under the terms of its respective
license. This file is compliance documentation, not legal advice.

## Linux x64 Ubuntu packages

- mpv `0.37.0-1ubuntu4` is extracted unmodified from Ubuntu 24.04. Its detailed
  per-file copyright and license grants are in
  `linux-x64/mpv/licenses/COPYRIGHT.Ubuntu`; the referenced GPL-2 and LGPL-2.1
  texts accompany it.
- FFmpeg and ffprobe `7:6.1.1-3ubuntu5` are extracted unmodified from Ubuntu
  24.04. The build is GPL-3.0-or-later because the linked Ubuntu codec stack
  enables GPL/version-3 components. Package copyright details and the GPL/LGPL
  texts are under `linux-x64/ffmpeg/licenses/`.
- MeCab `0.996-14ubuntu4` and `libmecab.so.2.0.0` are Ubuntu package files.
  This redistribution selects MeCab's BSD 3-clause option; Ubuntu's full
  copyright record and alternative GPL/LGPL texts are under
  `linux-x64/mecab/licenses/`.
- IPADIC `2.7.0-20070801+main-3` is compiled as UTF-8 from Ubuntu's exact source
  package. Its NAIST/ICOT copyright and redistribution terms are in
  `linux-x64/mecab/licenses/COPYRIGHT.IPADIC-Ubuntu`.

The Ubuntu package copyright files retain notices for every included source
file. System shared libraries declared in `LINUX_X64_DEPENDENCIES.md` are not
copied into this repository and remain subject to their installed package
licenses.
