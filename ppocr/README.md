# `ppocr/` — PP-OCRv5 on ONNX Runtime (in progress)

The replacement for `paddleocr/`: the same PP-OCRv5 mobile detector and
recogniser, run through ONNX Runtime instead of Paddle Inference. Measured on a
Ryzen 7 5800X3D against `scripts/testdata/game-capture-1080p.png`, it reads the
same five Japanese lines in **80 ms p50 against the shipped worker's 1525 ms**,
from a **39 MB payload against 352 MB**.

Nothing is staged here yet. This directory holds the sources and inputs that
have to be version-controlled; `scripts/build-ppocr-onnx-win-x64.ps1` downloads,
verifies and prepares everything else, builds `ppocr.exe` and leaves it runnable
in its build tree. Staging the payload itself — the binaries, the manifest
entries, the checksums and the notices — lands with
[#16](https://github.com/crpcrp/kizuna-vendor/issues/16).

## What is committed, and what is not

Payloads in this repository are built on a developer's Windows x64 machine and
only the finished artifacts are committed — never the toolchain, the downloaded
archives, the unpacked dependency trees or the CMake build directories. Those
live under the build script's `$WorkRoot` — `C:\kizuna\build-tools\ppocr` by
default, alongside every other payload's build tree — outside the repository,
and are a durable cache that costs no network to reuse.

So this directory tracks exactly these kinds of file:

| Path | Why it is in git |
|---|---|
| `worker/*` | Kizuna's own source: the JSONL worker and the CMake target that links it. Also the executable's GPL corresponding source. |
| `models/keys.txt` | An input the build cannot derive without the payload being deleted in the cleanup issue. |
| `patches/*.patch` | The modifications made to a third-party engine. They are both the build recipe and the Apache-2.0 corresponding-source record. |
| `tools/extract-keys.py` | Regenerates and cross-checks `keys.txt`, so the derivation survives without the spike branch. |
| `licenses/*`, `LICENSING.md` | The licence texts that must travel with the binary, and the review that says why. See [LICENSING.md](LICENSING.md). |

Everything else — ONNX Runtime, the OpenCV build, the unpacked engine source,
the `.onnx` weights — is fetched and rebuilt from the pinned URLs and SHA-256
hashes recorded in the build script. That script is the durable record of how
this payload is produced.

## Building

```powershell
./scripts/build-ppocr-onnx-win-x64.ps1
```

Requires Visual Studio 2022 or newer with the C++ x64 workload plus its bundled
CMake and Ninja, and 7-Zip. The first run downloads ~350 MB and spends about a
minute compiling a minimal static OpenCV; later runs rebuild only the worker, in
a few seconds. `-Clean` discards the unpacked engine source and both build
directories without throwing away the downloads.

The script header carries the decisions behind each pin, the licence of every
input, and why DirectML is absent. Read it before changing a version.

It leaves a runnable worker in `$WorkRoot\out`, laid out the way the payload
will be. Drive it through the protocol with:

```powershell
./scripts/verify-ppocr-onnx-win-x64.ps1
```

which checks protocol parity point by point against the committed 1080p
fixture, reports startup and warm latency, and draws the returned quadrilaterals
over the fixture so the coordinates can be looked at rather than trusted.

## The worker

`worker/ppocr_worker.cc` speaks the same newline-delimited JSON protocol as
`paddleocr/worker/paddleocr_worker.cc`, version 1, frame for frame — that
protocol, not the engine, is what Kizuna depends on. What changed underneath:

- Paddle Inference became ONNX Runtime through the patched engine, so a capture
  costs **91 ms p50 against 1518 ms** end to end through the protocol, measured
  on the same machine and fixture with each payload's own verification script.
- **No temporary file per request.** PaddleOCR's batch sampler dispatched on a
  file suffix, so every capture went to disk and back; `cv::imdecode` takes the
  bytes directly.
- `--det-model` and `--rec-model` name `.onnx` files rather than directories,
  and `--keys` is new and required.
- ONNX Runtime's thread count is set from the **physical** core count. Its own
  default is every logical processor, which the spike measured as a 2x loss on
  an eight-core SMT desktop (8 threads 79 ms, 16 threads 169 ms).
- Recognition runs through `getTextLinesBatched(8, 320)` from `patches/0002`.
- The engine reports model setup with `printf`, and **stdout carries the
  protocol**, so stdout is pointed at stderr while the engine is being built.
  That keeps the `total keys size(18385)` assertion visible without it ever
  landing in a protocol frame.
- The worker itself checks that `models/keys.txt` has exactly 18383 entries
  before loading anything, because the failure mode is silent garbage.

The tuning knobs the Paddle worker exposes — `--det-side-len`, `--cpu-threads`,
`--rec-batch-size` — are deliberately absent for now and land with
[#14](https://github.com/crpcrp/kizuna-vendor/issues/14). The defaults are what
the Paddle worker asks PaddleOCR for today: detection side 960, box threshold
0.6, unclip ratio 1.5, no angle classification.

The protocol is five message shapes, so the worker reads and writes them
directly instead of linking a JSON library. That keeps the reviewed dependency
set in [LICENSING.md](LICENSING.md) exactly as it stands: the Paddle worker's
`nlohmann/json` reached it through PaddleOCR's own vendored tree, which this
payload does not have.

## The engine

[`RapidAI/RapidOcrOnnx`](https://github.com/RapidAI/RapidOcrOnnx) at
`abd498c`, vendored as a pinned commit and patched — not tracked as a
dependency. Its last functional change was 2024-10-22 and its CI still pins
ONNX Runtime 1.15.1, so we own the patches.

It was chosen because there is no alternative: PaddleOCR's official
`deploy/cpp_infer` is Paddle Inference only (`SUPPORT_RUN_MODE` is
`{paddle, paddle_fp16, mkldnn, mkldnn_bf16}`, and it contains no `Ort::Session`
anywhere), so the real choice was patching this or writing the pipeline from
scratch. Its PP-OCRv5 compatibility is measured — 5/5 fixture lines byte-exact —
rather than assumed.

`patches/0001` is correctness: the official ONNX Runtime include layout, an
initialised `Ort::Session*` in every net (upstream leaves them wild, so any
failure before `initModel` becomes an access violation in the destructor rather
than a reportable error), CR stripping when reading `keys.txt`, and a UTF-8
`strToWstr` — the old one widened byte by byte and mangled any non-ASCII model
path, which this repository's own checkout path has.

`patches/0002` adds batched fixed-width recognition: one `[N,3,48,320]` `Run`
instead of upstream's one-`Run`-per-region loop at a width that changes with
every crop. Worth 90 → 80 ms on CPU. It inherits PaddleOCR's own limitation —
a region wider than the target aspect ratio is squashed rather than bucketed,
which is fine for dialogue crops and worth revisiting for full-width subtitles.

A third patch wires DirectML. It is parked on the `spike/ppocr-onnx-cpu` branch
and deliberately not applied; see the build script header for why.

## `models/keys.txt`

The PP-OCRv5 character dictionary: 18383 entries, LF, no trailing blank line,
`sha256 d1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b`.

It was extracted from the recogniser ONNX's own `character` metadata and
verified byte-identical to `PostProcess.character_dict` in
`paddleocr/models/rec/inference.yml`:

```powershell
python ppocr/tools/extract-keys.py `
  C:\kizuna\build-tools\ppocr\models\ch_PP-OCRv5_rec_mobile.onnx `
  ppocr/models/keys.txt `
  paddleocr/models/rec/inference.yml
```

Three properties decode to garbage if they are broken, and all three are caught
by asserting the runtime's `total keys size(18385)` print:

- **No leading blank entry.** The recogniser has 18385 output classes: index 0
  is the CTC blank, 1..18383 the dictionary, 18384 a space. RapidOcrOnnx
  prepends the blank and appends the space itself, so adding either to the file
  shifts every index by one.
- **LF only**, enforced by `.gitattributes`. Upstream reads with `getline` and
  keeps a CR; `0001` strips it defensively but the file should not need it.
- The first entry is U+3000 IDEOGRAPHIC SPACE — a real character, not padding —
  and ten entries are multi-codepoint flag emoji, so a reader that assumes one
  codepoint per line is wrong.

## Licensing

`ppocr.exe` will be conveyed under GPL-3.0-or-later, the way `paddleocr.exe` is
today: everything it links — RapidOcrOnnx and OpenCV (Apache-2.0), clipper
(BSL-1.0), zlib, libpng — is one-way compatible with GPLv3, and
`onnxruntime.dll` beside it stays MIT. [LICENSING.md](LICENSING.md) carries the
full review, the Apache-2.0 §4(b) modification notice for the patched engine,
the two-upstream provenance of the model weights, and the checklist the
staging issue has to satisfy before anything is published.

## Where the rest of the knowledge lives

- [#11](https://github.com/crpcrp/kizuna-vendor/issues/11) — the spike: every
  measurement, the provider-placement evidence, and the CPU-over-DirectML
  decision.
- [`spike/ppocr-onnx-cpu`](https://github.com/crpcrp/kizuna-vendor/tree/spike/ppocr-onnx-cpu)
  — the measurement harness, the raw run logs and the parked DirectML patch.
  Reference material, not a payload; nothing there is meant to reach `main`.
