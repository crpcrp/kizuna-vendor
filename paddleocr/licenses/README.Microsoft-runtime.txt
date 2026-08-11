Microsoft runtime files redistributed with the PaddleOCR payload
===============================================================

These are Microsoft redistributable components, not open-source project files,
so no upstream license text accompanies them in this mirror. They are copied
from the Visual Studio 2022 Build Tools redistributable directory recorded in
`scripts/build-paddleocr-win-x64.ps1`.

  paddleocr/bin/msvcp140.dll        Visual C++ runtime, VC143
  paddleocr/bin/vcruntime140.dll    Visual C++ runtime, VC143
  paddleocr/bin/vcruntime140_1.dll  Visual C++ runtime, VC143
  paddleocr/bin/concrt140.dll       Visual C++ runtime, VC143
  paddleocr/bin/vcomp140.dll        Visual C++ OpenMP runtime, VC143

`opencv_world4100.dll` imports the first four; `mkldnn.dll` imports
`vcomp140.dll`. Both also import the Universal CRT `api-ms-win-crt-*` API
sets, which ship with Windows 10 and 11 and are therefore not mirrored here.

These are "Distributable Code" under the Microsoft Visual Studio license
terms, which permit redistribution of the runtime files with an application:
https://visualstudio.microsoft.com/license-terms/

Copyright (c) Microsoft Corporation. All rights reserved.

This file is a provenance record, not legal advice. Confirm the current
Microsoft redistribution terms before shipping a build to end users.
