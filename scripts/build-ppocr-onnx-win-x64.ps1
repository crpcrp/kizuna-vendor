<#
.SYNOPSIS
    Stages the pinned inputs for the Windows x64 PP-OCR ONNX Runtime payload.

.DESCRIPTION
    Downloads and SHA-256 verifies ONNX Runtime, the RapidOcrOnnx engine source,
    the OpenCV sources and the PP-OCRv5 ONNX models; applies the Kizuna patches
    to RapidOcrOnnx; and builds a minimal static OpenCV. It then stops: the
    worker itself is built by a later issue.

    This is the ONNX Runtime successor to build-paddleocr-win-x64.ps1, which
    keeps working untouched until the cleanup issue retires it. The two never
    share a cache, so $WorkRoot defaults to C:\kzo rather than C:\kzb.

    Like its predecessor this is meant to be run on a developer's Windows x64
    box, not in CI: it needs Visual Studio 2022 or newer with the C++ x64
    workload (Build Tools is enough) plus its bundled CMake and Ninja, and
    7-Zip. $WorkRoot is a durable cache, so a rerun costs no network and reuses
    the OpenCV build. The first run downloads ~350 MB and spends a few minutes
    compiling OpenCV.

    Why this route at all: measured on a Ryzen 7 5800X3D, PP-OCRv5 on ONNX
    Runtime CPU reads the same five Japanese lines out of
    scripts/testdata/game-capture-1080p.png in 80 ms p50 against the shipped
    Paddle Inference worker's 1525 ms, from a 39 MB payload against 352 MB.
    See https://github.com/crpcrp/kizuna-vendor/issues/11 for the full spike.

.PARAMETER Clean
    Discards the unpacked engine source, the OpenCV build directory and the
    OpenCV install prefix before rebuilding. Downloads in $WorkRoot\dl are kept.
    Use after changing a pinned version, or to reproduce a build from scratch.

.NOTES
    Decisions this script encodes, per issue #12.

    1. ONNX Runtime version and package.

       Microsoft.ML.OnnxRuntime 1.24.4 — the plain CPU package. Headers, import
       library and runtime DLL all come from that one archive; never compile
       against one version's headers and load another at runtime.

       DirectML is deliberately absent. The spike measured it at 38 ms against
       CPU's 80 ms, but it costs +17.7 MB of payload, ~250 ms of per-process
       provider setup, a multi-second first-ever shader compile, adapter
       enumeration failure modes, and it is a net loss without batched
       recognition. It was never verified on non-NVIDIA hardware. CPU alone is
       already ~19x the shipped worker inside a 1-2 second interaction budget,
       and it is the only route that could ever serve the linux x64 payload.
       Patch 0003 on the spike branch keeps the DirectML wiring for later; it
       compiles out entirely without -D__DIRECTML__ and is not applied here.

    2. The character dictionary.

       Committed as ppocr/models/keys.txt rather than regenerated, because the
       cleanup issue deletes paddleocr/ and a build that reads from a directory
       being removed would break. It was extracted from the recogniser ONNX's
       own `character` metadata (spike/ppocr-onnx-cpu/tools/extract-keys.py on
       branch spike/ppocr-onnx-cpu regenerates it) and verified byte-identical
       to PostProcess.character_dict in paddleocr/models/rec/inference.yml.

       18383 entries, LF, no leading blank line. The recogniser has 18385
       output classes: index 0 is the CTC blank, 1..18383 the dictionary, 18384
       a space. RapidOcrOnnx prepends the blank and appends the space itself, so
       adding either to the file shifts every index and decodes to garbage.

    Why an engine whose base predates PP-OCRv5: there is no alternative. The
    official PaddleOCR deploy/cpp_infer is Paddle Inference only - its
    SUPPORT_RUN_MODE is {paddle, paddle_fp16, mkldnn, mkldnn_bf16} and it
    contains no Ort::Session anywhere - so the choice was patching RapidOcrOnnx
    or writing the pipeline from scratch. We vendor one pinned commit rather
    than follow a branch, and its PP-OCRv5 compatibility is measured (5/5 lines
    byte-exact) rather than assumed.

    Licences of the pinned inputs. Full notice wiring lands with the staging
    issue; this is the record of what enters the payload:

        ONNX Runtime 1.24.4        MIT
        RapidOcrOnnx abd498c       Apache-2.0, vendored and patched
        OpenCV 4.14.0              Apache-2.0, built from source here
        PP-OCRv5 det/rec weights   Baidu / Apache-2.0, via the ModelScope
                                   RapidAI mirror rather than PaddlePaddle

    Unlike the Paddle build, this one drives CMake through Ninja, so the Visual
    Studio generator name no longer has to be pinned - any instance carrying
    vcvars64.bat plus the bundled CMake and Ninja will do.
#>
[CmdletBinding()]
param(
    [string]$WorkRoot = 'C:\kzo',
    [string]$SevenZip = "$env:ProgramFiles\7-Zip\7z.exe",
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Payload = Join-Path $RepoRoot 'ppocr'

# Pinned inputs. Update every hash together with the version it belongs to.
$OnnxRuntimeVersion = '1.24.4'
$RapidOcrOnnxCommit = 'abd498c13a6dbe5f3b3c0d421d72e01bb3e6ee6d'
$OpenCvVersion = '4.14.0'
$ModelRevision = 'v3.9.2'

# Each archive names the directory it unpacks into, relative to $WorkRoot, so a
# rerun can skip both the download and the extraction once it is present. A null
# Unpacks means the download is used as a file, and is re-verified every run.
$Archives = @(
    @{
        # The CPU package. Its build/native/include headers, its
        # runtimes/win-x64/native/onnxruntime.lib import library and its
        # onnxruntime.dll are the only ONNX Runtime this payload ever sees.
        Name    = 'onnxruntime-cpu.nupkg'
        Url     = "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/$OnnxRuntimeVersion/microsoft.ml.onnxruntime.$OnnxRuntimeVersion.nupkg"
        Sha256  = '4b978d5065b85e7004b6c6f60ca494bd978fbe6836cbf0a0b52d82b61ab99638'
        Unpacks = 'onnxruntime'
    },
    @{
        # An immutable commit archive, not a branch or a release tag: upstream's
        # last functional change was 2024-10-22 and its CI still pins ONNX
        # Runtime 1.15.1, so this is vendored source we own and patch.
        Name    = 'rapidocronnx-src.tar.gz'
        Url     = "https://github.com/RapidAI/RapidOcrOnnx/archive/$RapidOcrOnnxCommit.tar.gz"
        Sha256  = '059a5fb008dbc7d5d0e7606e73f23a649b86000f0ddc696051abd02aea56edab'
        Unpacks = "RapidOcrOnnx-$RapidOcrOnnxCommit"
    },
    @{
        # The same self-extracting package the Paddle build uses, but for its
        # opencv\sources tree rather than its prebuilt binaries: 4.14.0 ships no
        # staticlib set any more and its opencv_world DLL is 76 MB, which would
        # undo most of the size win. Built minimally below, the whole linked
        # worker comes to under 5 MB with OpenCV inside it.
        Name    = 'opencv-windows.exe'
        Url     = "https://github.com/opencv/opencv/releases/download/$OpenCvVersion/opencv-$OpenCvVersion-windows.exe"
        Sha256  = '5f266a8b73bed535962d7e861a6457e32a0dd5f463ad0a7cf8707a135469be63'
        Unpacks = 'opencv'
    },
    @{
        Name    = 'ch_PP-OCRv5_det_mobile.onnx'
        Url     = "https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/$ModelRevision/onnx/PP-OCRv5/det/ch_PP-OCRv5_det_mobile.onnx"
        Sha256  = '4d97c44a20d30a81aad087d6a396b08f786c4635742afc391f6621f5c6ae78ae'
        Unpacks = $null
    },
    @{
        # PP-OCRv5's "ch" recogniser is the multilingual one and covers Japanese
        # in the same weights, matching what the Paddle payload loads today.
        Name    = 'ch_PP-OCRv5_rec_mobile.onnx'
        Url     = "https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/$ModelRevision/onnx/PP-OCRv5/rec/ch_PP-OCRv5_rec_mobile.onnx"
        Sha256  = '5825fc7ebf84ae7a412be049820b4d86d77620f204a041697b0494669b1742c5'
        Unpacks = $null
    }
)

# Applied in order to the pinned RapidOcrOnnx checkout, fail-closed. 0003 on the
# spike branch wires DirectML and is deliberately not listed; see the notes.
$Patches = @(
    '0001-Build-against-the-official-ONNX-Runtime-layout-and-s.patch',
    '0002-Add-batched-fixed-width-recognition-and-session-prof.patch'
)

function Assert-Path {
    param([string]$Path, [string]$What)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$What not found at $Path"
    }
}

function Get-VerifiedArchive {
    param([hashtable]$Archive, [string]$Destination)

    $target = Join-Path $Destination $Archive.Name
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Host "Downloading $($Archive.Name)"
        $previous = $ProgressPreference
        # Invoke-WebRequest's progress bar costs more than the transfer itself
        # on large archives under Windows PowerShell 5.1.
        $ProgressPreference = 'SilentlyContinue'
        # Download beside the target and rename only once the transfer finished,
        # so an interrupted 200 MB fetch cannot leave a truncated file that every
        # later run rejects as a hash mismatch. -TimeoutSec 0 because the default
        # gives up partway through the OpenCV package on a slow link.
        $partial = "$target.part"
        try {
            Invoke-WebRequest -Uri $Archive.Url -OutFile $partial -UseBasicParsing -TimeoutSec 0
            Move-Item -LiteralPath $partial -Destination $target -Force
        } finally {
            $ProgressPreference = $previous
            Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        }
    }

    $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Archive.Sha256) {
        throw "$($Archive.Name) SHA-256 mismatch: expected $($Archive.Sha256), got $actual"
    }
    Write-Host "Verified $($Archive.Name)"
    return $target
}

# Picks a Visual Studio instance carrying the x64 toolset plus the bundled CMake
# and Ninja. `vswhere -latest` alone is not enough: a Build Tools instance can be
# installed without the CMake component.
function Get-BuildToolchain {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    Assert-Path -Path $vswhere -What 'vswhere'

    $instances = & $vswhere -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -format json | ConvertFrom-Json
    if (-not $instances) { throw 'No Visual Studio instance with the C++ x64 toolset is installed' }

    foreach ($instance in $instances | Sort-Object installationVersion -Descending) {
        $vcvars = Join-Path $instance.installationPath 'VC\Auxiliary\Build\vcvars64.bat'
        $cmake = Join-Path $instance.installationPath `
            'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
        $ninja = Join-Path $instance.installationPath `
            'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe'
        if ((Test-Path -LiteralPath $vcvars) -and (Test-Path -LiteralPath $cmake) -and
            (Test-Path -LiteralPath $ninja)) {
            return @{
                Root    = $instance.installationPath
                Version = $instance.installationVersion
                Vcvars  = $vcvars
                CMake   = $cmake
                Ninja   = $ninja
            }
        }
    }
    throw 'No Visual Studio instance carries vcvars64.bat, the bundled CMake and the bundled Ninja'
}

Assert-Path -Path $SevenZip -What '7-Zip'
$toolchain = Get-BuildToolchain
Write-Host "Toolchain: MSVC $($toolchain.Version) at $($toolchain.Root)"

$downloads = Join-Path $WorkRoot 'dl'
$models = Join-Path $WorkRoot 'models'
$ortRoot = Join-Path $WorkRoot 'onnxruntime'
$engineRoot = Join-Path $WorkRoot "RapidOcrOnnx-$RapidOcrOnnxCommit"
$opencvRoot = Join-Path $WorkRoot 'opencv'
$opencvSrc = Join-Path $opencvRoot 'opencv\sources'
$opencvBuild = Join-Path $WorkRoot 'ocv'
$opencvPrefix = Join-Path $WorkRoot 'opencv-min'

if ($Clean) {
    Write-Host 'Clean build: discarding the engine source, the OpenCV build and its install prefix'
    Remove-Item -LiteralPath $engineRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $opencvBuild -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $opencvPrefix -Recurse -Force -ErrorAction SilentlyContinue
}
foreach ($dir in @($WorkRoot, $downloads, $models)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

# Fetch only what is not already unpacked, so a rebuild costs no network.
$paths = @{}
foreach ($archive in $Archives) {
    if ($archive.Unpacks -and (Test-Path -LiteralPath (Join-Path $WorkRoot $archive.Unpacks))) {
        Write-Host "Reusing $($archive.Unpacks)"
        continue
    }
    $paths[$archive.Name] = Get-VerifiedArchive -Archive $archive -Destination $downloads
}

if ($paths.ContainsKey('onnxruntime-cpu.nupkg')) {
    # A .nupkg is a zip.
    & $SevenZip x -y "-o$ortRoot" $paths['onnxruntime-cpu.nupkg'] | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not extract ONNX Runtime' }
}
if ($paths.ContainsKey('opencv-windows.exe')) {
    & $SevenZip x -y "-o$opencvRoot" $paths['opencv-windows.exe'] | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not extract OpenCV' }
}

$ortInclude = Join-Path $ortRoot 'build\native\include'
$ortLib = Join-Path $ortRoot 'runtimes\win-x64\native\onnxruntime.lib'
$ortDll = Join-Path $ortRoot 'runtimes\win-x64\native\onnxruntime.dll'
Assert-Path -Path (Join-Path $ortInclude 'onnxruntime_cxx_api.h') -What 'the ONNX Runtime C++ headers'
Assert-Path -Path $ortLib -What 'the ONNX Runtime import library'
Assert-Path -Path $ortDll -What 'the ONNX Runtime runtime library'
Assert-Path -Path (Join-Path $opencvSrc 'CMakeLists.txt') -What 'the OpenCV sources'

# The engine tree is patched exactly once, right after it is unpacked. The marker
# records which patches produced the tree that is there now, so a rerun neither
# re-applies them onto an already-patched checkout nor silently reuses a tree
# built from a different patch set.
$patchMarker = Join-Path $engineRoot '.kizuna-patched'
if ($paths.ContainsKey('rapidocronnx-src.tar.gz')) {
    & tar -xzf $paths['rapidocronnx-src.tar.gz'] -C $WorkRoot
    if ($LASTEXITCODE -ne 0) { throw 'Could not extract the RapidOcrOnnx source' }
    Assert-Path -Path $engineRoot -What 'the unpacked RapidOcrOnnx source'

    foreach ($patch in $Patches) {
        $patchPath = Join-Path $Payload "patches\$patch"
        Assert-Path -Path $patchPath -What "the patch $patch"
        # git apply works outside a repository and reports a nonzero exit code on
        # any rejected hunk, which must stop the build rather than warn: an
        # unpatched engine compiles against the wrong include layout and turns
        # every session failure into an access violation.
        # A "src/OcrUtils.cpp has type 100644, expected 100755" warning here is
        # expected and harmless: the tarball drops the executable bit that
        # upstream records. Only the exit code decides.
        & git -C $engineRoot apply --whitespace=nowarn -- $patchPath
        if ($LASTEXITCODE -ne 0) { throw "Failed to apply $patch to $engineRoot" }
        Write-Host "Applied $patch"
    }
    Set-Content -LiteralPath $patchMarker -Value $Patches -Encoding ascii
} else {
    if (-not (Test-Path -LiteralPath $patchMarker)) {
        # Only reachable after a patch was rejected: the tree is unpacked but
        # half-patched, and is left in place to be inspected.
        throw "$engineRoot is unpatched or half-patched; rerun with -Clean"
    }
    $applied = @(Get-Content -LiteralPath $patchMarker)
    if (Compare-Object -ReferenceObject $applied -DifferenceObject $Patches -SyncWindow 0) {
        throw "$engineRoot was patched with a different set; rerun with -Clean"
    }
    Write-Host "Reusing the patched engine source ($($applied.Count) patches)"
}

# Minimal static OpenCV: core, imgproc and imgcodecs with PNG only, static CRT,
# no IPP/OpenCL/protobuf/video. This is what keeps the linked worker under 5 MB
# and removes an OpenCV DLL from the runtime closure entirely.
if (Test-Path -LiteralPath (Join-Path $opencvPrefix 'x64')) {
    Write-Host 'Reusing the minimal static OpenCV'
} else {
    $opencvScript = Join-Path $WorkRoot 'build-opencv.bat'
    @"
@echo off
call "$($toolchain.Vcvars)" >nul || exit /b 1
"$($toolchain.CMake)" -S "$opencvSrc" -B "$opencvBuild" -G Ninja ^
  -DCMAKE_MAKE_PROGRAM="$($toolchain.Ninja)" ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_INSTALL_PREFIX="$opencvPrefix" ^
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded ^
  -DBUILD_SHARED_LIBS=OFF ^
  -DBUILD_LIST=core,imgproc,imgcodecs ^
  -DBUILD_opencv_apps=OFF -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOCS=OFF ^
  -DBUILD_JAVA=OFF -DBUILD_opencv_python2=OFF -DBUILD_opencv_python3=OFF -DBUILD_opencv_js=OFF ^
  -DBUILD_ZLIB=ON -DBUILD_PNG=ON ^
  -DBUILD_JPEG=OFF -DBUILD_TIFF=OFF -DBUILD_WEBP=OFF -DBUILD_OPENJPEG=OFF -DBUILD_JASPER=OFF -DBUILD_OPENEXR=OFF ^
  -DWITH_JPEG=OFF -DWITH_TIFF=OFF -DWITH_WEBP=OFF -DWITH_OPENJPEG=OFF -DWITH_JASPER=OFF -DWITH_OPENEXR=OFF -DWITH_AVIF=OFF -DWITH_GIF=OFF -DWITH_SPNG=OFF ^
  -DWITH_IPP=OFF -DWITH_OPENCL=OFF -DWITH_PROTOBUF=OFF -DWITH_FFMPEG=OFF -DWITH_MSMF=OFF -DWITH_DSHOW=OFF ^
  -DWITH_EIGEN=OFF -DWITH_ADE=OFF -DWITH_QUIRC=OFF -DWITH_LAPACK=OFF -DWITH_VTK=OFF -DWITH_ITT=OFF -DWITH_OBSENSOR=OFF ^
  -DVIDEOIO_ENABLE_PLUGINS=OFF -DHIGHGUI_ENABLE_PLUGINS=OFF -DOPENCV_ENABLE_NONFREE=OFF ^
  -DCV_TRACE=OFF -DOPENCV_GENERATE_PKGCONFIG=OFF -DOPENCV_GENERATE_SETUPVARS=OFF || exit /b 1
"$($toolchain.CMake)" --build "$opencvBuild" --target install || exit /b 1
"@ | Set-Content -LiteralPath $opencvScript -Encoding ascii

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    & cmd /c "`"$opencvScript`""
    if ($LASTEXITCODE -ne 0) { throw "The OpenCV build failed with exit code $LASTEXITCODE" }
    $timer.Stop()
    Write-Host "Built OpenCV in $([math]::Round($timer.Elapsed.TotalSeconds)) s"
}

$opencvConfig = Get-ChildItem -LiteralPath $opencvPrefix -Recurse -Filter 'OpenCVConfig.cmake' `
    -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -like '*staticlib' } |
    Select-Object -First 1
if (-not $opencvConfig) { throw "No static OpenCVConfig.cmake under $opencvPrefix" }
$opencvDir = $opencvConfig.DirectoryName

# The models and the dictionary sit together, the way the worker will be given
# them. keys.txt is committed rather than derived; see the notes above.
$keys = Join-Path $Payload 'models\keys.txt'
Assert-Path -Path $keys -What 'the committed PP-OCRv5 character dictionary'
foreach ($model in @('ch_PP-OCRv5_det_mobile.onnx', 'ch_PP-OCRv5_rec_mobile.onnx')) {
    Copy-Item -LiteralPath $paths[$model] -Destination (Join-Path $models $model) -Force
}
Copy-Item -LiteralPath $keys -Destination (Join-Path $models 'keys.txt') -Force

# TODO(#13): build the worker. It links the patched engine sources
# (src\DbNet.cpp, src\CrnnNet.cpp, src\OcrUtils.cpp, src\clipper.cpp) and the
# Kizuna JSONL entry point against $ortInclude / $ortLib and $opencvDir, then
# stages the executable, onnxruntime.dll, both models and keys.txt into ppocr/.

Write-Host ''
Write-Host 'Staged, ready for the worker build:'
Write-Host "  ONNX Runtime $OnnxRuntimeVersion  $ortRoot"
Write-Host "    headers    $ortInclude"
Write-Host "    import lib $ortLib"
Write-Host "    runtime    $ortDll"
Write-Host "  RapidOcrOnnx $($RapidOcrOnnxCommit.Substring(0, 7)), patched  $engineRoot"
Write-Host "  OpenCV $OpenCvVersion static  $opencvDir"
Write-Host "  Models and dictionary  $models"
Write-Host ''
Write-Host 'Nothing was staged into ppocr/: the worker build lands with issue #13.'
