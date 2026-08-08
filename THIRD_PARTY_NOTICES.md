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
