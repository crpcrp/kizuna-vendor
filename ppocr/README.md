# PP-OCRv5 ONNX worker

This is the Windows Game OCR runtime. It replaced a Paddle Inference payload
that has since been retired: on the committed 1080p fixture it reads the same
five Japanese lines in about 80 ms p50 where that worker took about 1.5 s, and
the prepared runtime is about 41 MB instead of 352 MB.

The complete staged payload lives in this directory. It is built from pinned
inputs, hashed in `SHA256SUMS.txt`, described by the `ppocr` manifest component,
and covered by the repository notices.

## Build and verify

Use Windows x64 with Visual Studio 2022 or newer, its C++ x64/CMake/Ninja
components, and 7-Zip:

```powershell
./scripts/build-ppocr-onnx-win-x64.ps1
./scripts/refresh-ppocr-onnx-hashes.ps1
./scripts/verify-ppocr-onnx-win-x64.ps1
```

The build cache defaults to `C:\kizuna\build-tools\ppocr`; `-Clean` rebuilds
from pinned sources without deleting downloads. A disposable runnable tree is
left under `out`, while the publishable runtime is staged here. Nothing in the
build cache belongs in git.

The payload and its corresponding source include:

| Path | Purpose |
|---|---|
| `worker/` | JSONL worker and CMake target; GPL corresponding source |
| `patches/` | reviewed RapidOcrOnnx changes applied by the build |
| `models/keys.txt` | exact PP-OCRv5 character dictionary |
| `tools/extract-keys.py` | dictionary regeneration and cross-check |
| `licenses/`, `LICENSING.md` | licence texts and compliance record |
| `bin/`, `models/*.onnx` | staged CPU runtime and PP-OCRv5 models |

The build script pins and verifies ONNX Runtime 1.24.4, RapidOcrOnnx
`abd498c`, OpenCV 4.14.0, and both PP-OCRv5 ONNX models. DirectML is not built:
the spike found CPU already meets the interaction budget with a smaller,
cross-platform-compatible runtime.

## Worker contract

`worker/ppocr_worker.cc` implements the protocol-v1 JSON-lines contract the
Paddle worker also spoke. It decodes captures in memory, keeps all non-protocol
logging on stderr, validates the 18,383-entry dictionary, and stays alive after
bad requests.

Required options are `--protocol-version 1`, `--lang japan`, `--det-model`,
`--rec-model`, and `--keys`. Tuning defaults are:

| Option | Default |
|---|---:|
| `--det-side-len` | `960` |
| `--det-limit-type` | `max` |
| `--det-thresh` / `--det-box-thresh` | `0.3` / `0.6` |
| `--det-unclip-ratio` | `1.5` |
| `--rec-score-thresh` | `0` |
| `--cpu-threads` | physical cores, max 16 |
| `--rec-batch-size` / `--rec-width` | `8` / `320` |

`--mkldnn-cache`, `--det-model-name`, and `--rec-model-name` are accepted for
Paddle-era callers and ignored with a startup note. The source header records
validation ranges.

Measured at eight threads on `scripts/testdata/game-capture-1080p.png`:

| detection side | 480 | 640 | 736 | 960 | 1280 | 1920 |
|---:|---:|---:|---:|---:|---:|---:|
| warm p50 | 55 ms | 64 ms | 67 ms | 83 ms | 112 ms | 253 ms |
| correct lines | 5/5 | 5/5 | 5/5 | 5/5 | 5/5 | 5/5 |

On the 8-core/16-thread spike host, 1/2/4/8/16 threads measured
205/119/83/79/169 ms. The default therefore uses physical cores rather than
logical processors.

## Engine and dictionary

RapidOcrOnnx is treated as vendored source, not a maintained dependency:

- `0001` uses the official ONNX Runtime layout, initializes session pointers,
  handles UTF-8 paths, and fixes tensor counts and unclip-result iteration.
- `0002` adds fixed-width batched recognition and profiling hooks.

Official PaddleOCR has no standalone C++ ONNX Runtime pipeline; its C++ deploy
path still links Paddle Inference. The spike and measurements behind this
choice are in [issue #11](https://github.com/crpcrp/kizuna-vendor/issues/11).

`models/keys.txt` has 18,383 LF-delimited entries. It is extracted from the
recognizer model's `character` metadata and matches PaddleOCR's
`PostProcess.character_dict` byte-for-byte. Do not add a leading blank or
trailing space: RapidOcrOnnx supplies the CTC blank and final space itself.
Regenerate it with:

```powershell
python ppocr/tools/extract-keys.py `
  C:\kizuna\build-tools\ppocr\models\ch_PP-OCRv5_rec_mobile.onnx `
  ppocr/models/keys.txt
```

The tool takes an optional third argument to cross-check the extracted list
against a Paddle `inference.yml`. No such file is in the repository any more;
the dictionary now comes from the weights it belongs to.

See [LICENSING.md](LICENSING.md) before staging or redistributing the runtime.
