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

## PaddleOCR and the Windows OCR runtime

- Build: `paddleocr.exe` combines Kizuna's GPL-3.0-or-later worker entrypoint
  with PaddleOCR `v3.7.0`'s `deploy/cpp_infer`, compiled with the installed
  MSVC v143 (Visual Studio 2022 Build Tools), Release x64. The worker source,
  patch, and recipe are under `paddleocr/worker/` and `scripts/`.
- Copyright © PaddlePaddle Authors; Apache-2.0
  (`paddleocr/licenses/LICENSE.PaddleOCR.txt`).
- The redistributed shared libraries and their terms:
  - `paddle_inference.dll`, `phi.dll`, `common.dll` — Paddle Inference 3.2.0,
    Apache-2.0 (`paddleocr/licenses/LICENSE.Paddle.txt`).
  - `mkldnn.dll` — oneDNN 3.6.2, Apache-2.0
    (`paddleocr/licenses/LICENSE.oneDNN.txt`, with its bundled third-party
    notices in `paddleocr/licenses/THIRD-PARTY-PROGRAMS.oneDNN.txt`).
  - `mklml.dll` and `libiomp5md.dll` — Intel MKL small libraries
    `2019.0.5.20190502`, Copyright © 2018 Intel Corporation, under the Intel
    Simplified Software License (April 2018). That license requires the
    copyright notice and its terms of use to travel with the software, so
    both `paddleocr/licenses/LICENSE.Intel-MKLML.txt` and
    `paddleocr/licenses/THIRD-PARTY-PROGRAMS.Intel-MKLML.txt` must be
    reproduced in any redistribution.
  - `opencv_world4100.dll` — OpenCV 4.10.0, Apache-2.0
    (`paddleocr/licenses/LICENSE.OpenCV.txt`).
  - `abseil_dll.dll` — Abseil, Apache-2.0
    (`paddleocr/licenses/LICENSE.Abseil.txt`).
  - `polyclipping.dll` — Clipper 6.4.2, Boost Software License 1.0
    (`paddleocr/licenses/LICENSE.Clipper.txt`).
  - `msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`,
    `concrt140.dll`, and `vcomp140.dll` — Microsoft distributable code,
    recorded in `paddleocr/licenses/README.Microsoft-runtime.txt`.
- Linked into `paddleocr.exe`: glog and gflags (BSD-3-Clause), protobuf
  (BSD-3-Clause), xxHash (BSD-2-Clause), yaml-cpp and nlohmann/json (MIT), and
  the tronkko `dirent` compatibility header (MIT, Copyright © 1998-2019 Toni
  Ronkko). Their texts accompany the payload under `paddleocr/licenses/`.
- The Paddle Inference package ships no license or notice files of its own.
  Components statically linked inside `paddle_inference.dll` are covered by
  PaddlePaddle's Apache-2.0 distribution and are not separately enumerated
  here; review that if the payload is redistributed outside Kizuna.
- No mirrored Apache-2.0 component ships an upstream `NOTICE` file, so no
  additional attribution notice is required beyond the license texts.

## PP-OCRv5 models

- Detection `PP-OCRv5_mobile_det` and recognition `PP-OCRv5_mobile_rec`,
  redistributed unmodified from PaddlePaddle's official inference archives.
- Copyright © PaddlePaddle Authors; released with PaddleOCR under Apache-2.0
  (`paddleocr/licenses/LICENSE.PaddleOCR.txt`).
- PP-OCRv5 recognition handles Simplified Chinese, Traditional Chinese,
  English, Japanese, and Pinyin in one model. Kizuna uses it for Japanese; the
  other scripts are an inseparable property of the weights, not an added
  language payload.

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
