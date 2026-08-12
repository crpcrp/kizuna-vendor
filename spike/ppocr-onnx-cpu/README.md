# PP-OCRv5 on ONNX Runtime — spike artifacts (#11)

Throwaway spike output for [#11](https://github.com/crpcrp/kizuna-vendor/issues/11),
kept on a branch so [#12](https://github.com/crpcrp/kizuna-vendor/issues/12) can
start from measured code rather than re-derive it. **Nothing here is a payload
and nothing here is meant to merge to `main` as-is.**

The decision the spike produced: **ship the CPU ONNX Runtime route, park
DirectML.** See the [#11 findings comment](https://github.com/crpcrp/kizuna-vendor/issues/11#issuecomment-5263536046)
for the full measurement set.

## What was measured

Ryzen 7 5800X3D (8C/16T), RTX 4070, 32 GB, Windows 11 Pro 26200, MSVC 14.51,
ONNX Runtime 1.24.4, OpenCV 4.14.0 built as a minimal static set. Fixture is
`scripts/testdata/game-capture-1080p.png`; correctness is the same five lines
`verify-paddleocr-win-x64.ps1` asserts. 30 warm runs after one warm-up.

| Route | warm p50 | warm p95 | 5/5 lines | staged size |
|---|---|---|---|---|
| Paddle Inference CPU (shipped today) | 1525 ms | — | yes | 352 MB |
| **ONNX Runtime CPU, batched rec** | **80 ms** | 86 ms | yes | **39 MB** |
| ONNX Runtime CPU, upstream rec loop | 90 ms | 96 ms | yes | 39 MB |
| ONNX Runtime + DirectML, batched rec *(parked)* | 38 ms | 40 ms | yes | 59 MB |
| ONNX Runtime + DirectML, upstream rec loop *(parked)* | 164 ms | 185 ms | yes | 59 MB |

CPU alone is ~19× the shipped worker against a 1–2 second interaction budget,
with no GPU dependency, no shader-compile cold start and no adapter failure
modes. Raw run logs are in `results/`.

Two CPU numbers worth carrying into #13 and #14:

- **Thread count matters and does not scale past physical cores.** 1 thread
  205 ms, 2 → 119 ms, 4 → 83 ms, 8 → 79 ms, **16 → 169 ms**. Do not let ONNX
  Runtime default to all logical processors on an SMT CPU. Even the
  single-threaded worst case is inside budget.
- **Detection side is a free knob on this fixture.** 5/5 lines at every size
  from 480 to 1920: 480 → 55 ms, 640 → 64 ms, 736 → 67 ms, 960 → 83 ms,
  1280 → 112 ms, 1920 → 253 ms.

## Layout

```
patches/    the three patches applied to RapidOcrOnnx, split by purpose
driver/     the standalone measurement harness used to produce the numbers
tools/      keys.txt extraction, ORT profile analysis, minimal OpenCV recipe
models/     keys.txt, ready to move to ppocr/models/ in #12
results/    raw output of every run quoted above and in the #11 comment
```

## The patches

Against `RapidAI/RapidOcrOnnx` at `abd498c` (2025-03-25, the tip of `main`;
last functional change 2024-10-22). Apply in order with `git apply`.

| Patch | Needed for the CPU route? |
|---|---|
| `0001-Build-against-the-official-ONNX-Runtime-layout-and-s.patch` | **yes, mandatory** |
| `0002-Add-batched-fixed-width-recognition-and-session-prof.patch` | **yes** |
| `0003-Wire-DirectML-into-detection-and-set-the-session-opt.patch` | no — parked for #15 |

`0001` does four things, three of which are correctness rather than taste:
the include paths move to the official Microsoft NuGet layout; every
`Ort::Session*` gets initialised (upstream leaves them wild, so *any* failure
before `initModel` becomes an access violation in the destructor instead of a
reportable error — this is what makes a clean fallback possible at all); a
trailing CR is stripped when reading `keys.txt`; and `strToWstr` stops widening
byte-by-byte, which mangled every non-ASCII model path.

`0002` adds `getTextLinesBatched`, which packs regions into one
`[N,3,48,W]` `Run` instead of upstream's one-`Run`-per-region loop at a width
that changes with every crop. Worth 90 → 80 ms on CPU. It carries PaddleOCR's
own limitation: a region wider than the target aspect ratio is squashed rather
than bucketed. Fine for dialogue crops; revisit for full-width subtitles.

`0003` compiles out entirely without `-D__DIRECTML__`.

Verified: `0001` + `0002` apply cleanly to a pristine `abd498c` checkout and the
resulting build reproduces 79.6 ms p50 with all five lines correct.

## Reproducing

```powershell
# 1. dependencies
#    ONNX Runtime CPU 1.24.4   https://www.nuget.org/api/v2/package/Microsoft.ML.OnnxRuntime/1.24.4
#    OpenCV 4.14.0 sources     https://github.com/opencv/opencv/releases/tag/4.14.0
tools\build-opencv-min.bat <opencv-sources> <build-dir> <opencv-prefix>

# 2. engine
git clone https://github.com/RapidAI/RapidOcrOnnx.git
git -C RapidOcrOnnx checkout abd498c
git -C RapidOcrOnnx apply ..\patches\0001-*.patch ..\patches\0002-*.patch

# 3. models
#    det https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.9.2/onnx/PP-OCRv5/det/ch_PP-OCRv5_det_mobile.onnx
#        4d97c44a20d30a81aad087d6a396b08f786c4635742afc391f6621f5c6ae78ae
#    rec https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.9.2/onnx/PP-OCRv5/rec/ch_PP-OCRv5_rec_mobile.onnx
#        5825fc7ebf84ae7a412be049820b4d86d77620f204a041697b0494669b1742c5
python tools\extract-keys.py rec.onnx models\keys.txt paddleocr\models\rec\inference.yml

# 4. harness
cmake -S driver -B build -G Ninja -DCMAKE_BUILD_TYPE=Release ^
      -DORT_DIR=<extracted-nuget> -DRAPID_DIR=<patched-checkout> -DUSE_DIRECTML=OFF
cmake --build build

build\ocrspike.exe --det det.onnx --rec rec.onnx --keys models\keys.txt ^
      --image ..\..\scripts\testdata\game-capture-1080p.png ^
      --rec-batch 8 --threads 8 --runs 30
```

## keys.txt

`models/keys.txt` is the PP-OCRv5 character dictionary, 18383 entries, LF, no
trailing blank. It was extracted from the recogniser ONNX's own `character`
metadata and verified byte-identical to `PostProcess.character_dict` in
`paddleocr/models/rec/inference.yml`.

The recogniser has **18385** output classes: index 0 is the CTC blank, 1..18383
are the dictionary, 18384 is a space. RapidOcrOnnx already prepends the blank
and appends the space itself, so this convention is correct as-is —
**do not add a leading blank line**, it shifts every index and decodes garbage.
The runtime print `total keys size(18385)` is a cheap assertion worth keeping.

Ten entries are multi-codepoint (regional-indicator flag emoji), so a reader
that assumes one codepoint per line is wrong.

## The driver is not the worker

`driver/main.cpp` is a measurement harness: it reads one image, loops, and
prints timings, provider placement, peak working set and GPU memory. #13 writes
the real worker by adapting `paddleocr/worker/paddleocr_worker.cc`, which owns
the JSONL protocol that actually matters. The only parts of the driver worth
copying are the `--threads` / `--max-side` / `--rec-batch` plumbing and the
stage-by-stage failure reporting.

Note the harness excludes protocol framing. PNG decode of the fixture measures
9 ms and is charged to the worker's per-request budget.
