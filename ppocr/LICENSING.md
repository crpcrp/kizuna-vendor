# `ppocr/` licensing

The licence review [#11](https://github.com/crpcrp/kizuna-vendor/issues/11)
flagged for a human, done ahead of the payload so nothing has to be
reconstructed later. It covers the dependency set the ONNX Runtime worker will
be built from, and the licence texts that have to travel with it are already
committed under `ppocr/licenses/`.

The staged binary, models, notices and corresponding source are distributed
together under `ppocr/`. The top-level `THIRD_PARTY_NOTICES.md`,
`CORRESPONDING_SOURCE.md`, `manifest.json` and `SHA256SUMS.txt` record and
verify that payload.

This is compliance documentation, not legal advice.

## The combined executable

`ppocr.exe` links, into one binary:

| Component | Version | Licence | Text |
|---|---|---|---|
| Kizuna's worker entry point | — | **GPL-3.0-or-later** | `licenses/LICENSE.GPLv3.txt` |
| RapidOcrOnnx pipeline, **modified** | `abd498c` | Apache-2.0 | `licenses/LICENSE.RapidOcrOnnx.txt` |
| Clipper, vendored inside RapidOcrOnnx | 6.4.2 | BSL-1.0 | `licenses/LICENSE.Clipper.txt` |
| OpenCV `core`, `imgproc`, `imgcodecs`, static | 4.14.0 | Apache-2.0 | `licenses/LICENSE.OpenCV.txt`, `licenses/COPYRIGHT.OpenCV.txt` |
| zlib, static, built by OpenCV | 1.3.2 | zlib licence | `licenses/LICENSE.zlib.txt` |
| libpng, static, built by OpenCV | 1.6.57 | PNG Reference Library License v2 | `licenses/LICENSE.libpng.txt` |
| MSVC C runtime, **statically** linked | VC143+ | Microsoft Distributable Code | `licenses/README.Microsoft-runtime.txt` |

and load one shared library beside it:

| Component | Version | Licence | Text |
|---|---|---|---|
| `onnxruntime.dll` | 1.24.4 | MIT | `licenses/LICENSE.ONNXRuntime.txt`, `licenses/THIRD-PARTY-NOTICES.ONNXRuntime.txt` |

**The whole executable is therefore conveyed under GPL-3.0-or-later**, exactly
as `paddleocr.exe` is today. Apache-2.0, BSL-1.0, the zlib licence and
libpng-2 are all one-way compatible with GPLv3, so each component keeps its own
terms inside the combined binary while the binary as a whole is GPL. Whoever
ships it must offer its corresponding source: the worker under `ppocr/worker/`,
the patches under `ppocr/patches/`, and `scripts/build-ppocr-onnx-win-x64.ps1`,
which pins every input by SHA-256 and is the "scripts used to control
compilation and installation" that GPLv3 §1 asks for.

`onnxruntime.dll` is a separate work, not derived from the worker, and keeps
its own MIT terms.

The worker's statically linked MSVC runtime is Microsoft "Distributable Code"
and is covered by the GPL's system-library exception, being a major component
of the operating system the executable runs on. Microsoft's prebuilt
`onnxruntime.dll` dynamically imports `msvcp140.dll`, `msvcp140_1.dll`,
`vcruntime140.dll` and `vcruntime140_1.dll`; those redistributable files are
therefore staged beside it. The Universal CRT API sets ship with Windows.

## Modification notice — RapidOcrOnnx (Apache-2.0 §4(b))

Apache-2.0 requires modified files to carry prominent notices stating that they
were changed. This is that notice, and it is deliberately not buried:

> Kizuna's `ppocr.exe` contains a **modified** copy of
> [RapidAI/RapidOcrOnnx](https://github.com/RapidAI/RapidOcrOnnx) at commit
> `abd498c13a6dbe5f3b3c0d421d72e01bb3e6ee6d`, Copyright © the RapidOcrOnnx
> authors, licensed under the Apache License 2.0. The changes are the two
> patches in `ppocr/patches/`, applied at build time by
> `scripts/build-ppocr-onnx-win-x64.ps1`:
>
> - `0001` — build against the official ONNX Runtime include layout, initialise
>   every `Ort::Session*`, open `keys.txt` through its UTF-8 path, strip a
>   trailing CR from its lines, widen model paths as UTF-8, and correct tensor
>   counts and unclip-result iteration.
> - `0002` — add batched fixed-width recognition and session profiling hooks.
>
> The files affected are `include/AngleNet.h`, `include/CrnnNet.h`,
> `include/DbNet.h`, `include/OcrLiteImpl.h`, `include/OcrUtils.h`,
> `src/AngleNet.cpp`, `src/CrnnNet.cpp`, `src/DbNet.cpp` and `src/OcrUtils.cpp`.

Keeping the changes as reviewable patches rather than a forked tree is what
makes this notice precise, and it satisfies the GPL source-offer duty for the
same files at the same time. No copyright, patent, trademark or attribution
notice was removed by either patch.

RapidOcrOnnx ships **no `NOTICE` file** — its repository contains only
`LICENSE` — so Apache-2.0 §4(d) adds nothing here. The same is true of OpenCV,
which carries `LICENSE` and `COPYRIGHT` and no `NOTICE`. OpenCV is built from
unmodified pinned sources; only the build configuration is ours.

## The PP-OCRv5 weights

`ch_PP-OCRv5_det_mobile.onnx` and `ch_PP-OCRv5_rec_mobile.onnx` are
redistributed unmodified, and have two upstreams:

- **The weights** are PaddleOCR's PP-OCRv5 mobile detection and recognition
  models, Copyright © PaddlePaddle Authors, released under Apache-2.0
  (`licenses/LICENSE.PaddleOCR.txt`). RapidOCR's own README is explicit that
  Baidu holds the model copyright while its engineering scripts are the
  project's.
- **The ONNX conversion** is [RapidAI/RapidOCR](https://github.com/RapidAI/RapidOCR)'s,
  also Apache-2.0, fetched from its ModelScope mirror at revision `v3.9.2`.

Both are Apache-2.0, so redistribution is clean, but the provenance matters and
should be stated rather than collapsed into "PaddlePaddle": these are not the
files PaddlePaddle publishes, they are a third party's conversion of them. The
pinned URLs and SHA-256 hashes in the build script are the record of exactly
which bytes were taken.

The recogniser's character dictionary, committed as `ppocr/models/keys.txt`, is
extracted from those weights' own metadata and inherits the same Apache-2.0
terms.

PP-OCRv5 recognition covers Simplified Chinese, Traditional Chinese, English,
Japanese and Pinyin in one model. Kizuna uses it for Japanese; the other
scripts are an inseparable property of the weights, not an added language
payload.

## Staging compliance checklist

Nothing below is a blocker for pinning or for building the worker — but the
payload must not be published until all of it is true:

- [x] A `## PP-OCR ONNX runtime` section in `THIRD_PARTY_NOTICES.md` carrying
      the two tables above, the modification notice, and the GPL-3.0-or-later
      conclusion.
- [x] A `ppocr` section in `CORRESPONDING_SOURCE.md` with the pinned URL and
      SHA-256 of every input, matching what the build script already records,
      and naming `ppocr/patches/` as the modifications.
- [x] `ppocr/licenses/` staged into the packaged build the way
      `paddleocr/licenses/` is, and copied to the notices location by Kizuna's
      packaging step.
- [x] The worker source kept beside the binary as its corresponding source, as
      `paddleocr/worker/` is today.
- [x] `THIRD-PARTY-NOTICES.ONNXRuntime.txt` shipped alongside `onnxruntime.dll`
      — it is Microsoft's own notice file for everything statically linked
      inside that DLL, and MIT's "all copies or substantial portions"
      requirement reaches it.
- [x] `manifest.json` and `SHA256SUMS.txt` entries, so a truncated licence file
      fails verification like any other payload file.

If the DirectML route is ever revived, `DirectML.dll` is a Microsoft
redistributable with its own terms and would need its own entry; nothing about
it is covered here.
