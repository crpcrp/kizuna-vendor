Microsoft runtime code in the PP-OCR ONNX payload
=================================================

Unlike the PaddleOCR payload, this one redistributes no Visual C++ runtime
DLLs. The worker and the OpenCV it links are both compiled with
/MT (CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded), so the C runtime is linked
statically into `ppocr.exe` and there is no `msvcp140.dll`,
`vcruntime140.dll`, `vcruntime140_1.dll` or `concrt140.dll` beside it.

  ppocr.exe          static MSVC C runtime, VC143 or newer
  onnxruntime.dll    Microsoft, MIT-licensed; see LICENSE.ONNXRuntime.txt

`ppocr.exe` and `onnxruntime.dll` both import the Universal CRT
`api-ms-win-crt-*` API sets, which ship with Windows 10 and 11 and are
therefore not mirrored here.

Static linking of the C runtime is permitted by the Visual Studio license
terms, which treat the runtime as "Distributable Code" and allow it to be
linked into an application:
https://visualstudio.microsoft.com/license-terms/

Because `ppocr.exe` is conveyed under GPL-3.0-or-later, note also that the
statically linked C runtime is a "System Library" in the GPLv3 sense — a major
component of the operating system the executable runs on — so it does not have
to be shipped as corresponding source.

The exact toolchain used for a given build is recorded by
`scripts/build-ppocr-onnx-win-x64.ps1`, which prints the selected MSVC version
and selects it through `vswhere`.

Copyright (c) Microsoft Corporation. All rights reserved.

This file is a provenance record, not legal advice. Confirm the current
Microsoft redistribution terms before shipping a build to end users.
