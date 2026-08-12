<#
.SYNOPSIS
    Rebuilds the Windows x64 PaddleOCR payload under paddleocr/.

.DESCRIPTION
    Downloads the pinned PaddleOCR source, Paddle Inference runtime, OpenCV
    package, and PP-OCRv5 models; verifies every archive by SHA-256; builds the
    persistent Kizuna worker with MSVC; and stages the result into paddleocr/.

    This script is meant to be run on a developer's Windows x64 box, not in CI.
    The dependency set is ~1.4 GB extracted and the from-scratch compile takes a
    couple of minutes, so $WorkRoot is a durable cache: an archive is fetched
    only when the directory it unpacks into is missing, and the CMake build
    directory is reused. A first run takes roughly ten minutes end to end
    (dominated by downloading Paddle Inference and OpenCV); later runs that only
    touch paddleocr/worker/paddleocr_worker.cc finish in well under a minute.

    Requires Visual Studio 2022 with the C++ x64 workload (Build Tools is
    enough) and 7-Zip. Then verify and commit:

        ./scripts/verify-paddleocr-win-x64.ps1
        git add paddleocr SHA256SUMS.txt manifest.json

.PARAMETER Clean
    Discards the unpacked source tree and the CMake build directory before
    building. Downloads in $WorkRoot\dl are kept. Use after changing a pinned
    version, or to reproduce a build from scratch.

.NOTES
    MSBuild's FileTracker fails once paths approach MAX_PATH, so the build runs
    under a working root near the root of the drive rather than in-tree. Every
    payload's build tree lives in its own directory under C:\kizuna\build-tools
    so nothing is scattered across the drive; keep any replacement short for
    the same reason.
#>
[CmdletBinding()]
param(
    [string]$WorkRoot = 'C:\kizuna\build-tools\paddleocr',
    [string]$SevenZip = "$env:ProgramFiles\7-Zip\7z.exe",
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Payload = Join-Path $RepoRoot 'paddleocr'

# Pinned inputs. Update every hash together with the version it belongs to.
$PaddleOcrVersion = 'v3.7.0'
$PaddleInferenceVersion = '3.2.0'
$OpenCvVersion = '4.10.0'
$DirentVersion = '1.24'

# Each archive names the directory it unpacks into, relative to $WorkRoot, so a
# rerun can skip both the download and the extraction once it is present.
$Archives = @(
    @{
        Name    = 'paddleocr-src.tar.gz'
        Url     = "https://github.com/PaddlePaddle/PaddleOCR/archive/refs/tags/$PaddleOcrVersion.tar.gz"
        Sha256  = '8e5f1f9ba18c29621d38394b4f72925960640b315281391c3b3c86804f079a73'
        Unpacks = "PaddleOCR-$($PaddleOcrVersion.TrimStart('v'))"
    },
    @{
        Name    = 'paddle_inference.zip'
        Url     = "https://paddle-inference-lib.bj.bcebos.com/$PaddleInferenceVersion/cxx_c/Windows/CPU/x86-64_avx-mkl-vs2019/paddle_inference.zip"
        Sha256  = '23a2ea41abaedb7dfb928dc10baa72975d50b7a8ffe28f8e081a16a8977a95b2'
        Unpacks = 'paddle_inference'
    },
    @{
        Name    = 'opencv-windows.exe'
        Url     = "https://github.com/opencv/opencv/releases/download/$OpenCvVersion/opencv-$OpenCvVersion-windows.exe"
        Sha256  = 'bff38466091c313dac21a0b73eea8278316a89c1d434c6f0b10697e087670168'
        Unpacks = 'opencv'
    },
    @{
        Name    = 'PP-OCRv5_mobile_det_infer.tar'
        Url     = 'https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv5_mobile_det_infer.tar'
        Sha256  = '50446e5d01ac2a73d5319c89513281f6578414c888c602f9af13f93feefffc58'
        Unpacks = 'models\PP-OCRv5_mobile_det_infer'
    },
    @{
        # The mobile recognizer, not the server one. Measured on a 1920x1080
        # capture across four renderings it read 19 of 20 Japanese lines against
        # the server model's 15, at 1.6-2.0 s per frame against 2.1-2.6 s.
        Name    = 'PP-OCRv5_mobile_rec_infer.tar'
        Url     = 'https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv5_mobile_rec_infer.tar'
        Sha256  = '566b9512b34e34a9f0db54d87b51fa5a0b9ed2cf1ab7e49728cc0b8b5a64f414'
        Unpacks = 'models\PP-OCRv5_mobile_rec_infer'
    },
    @{
        # PaddleOCR 3.7.0's utility.cc includes <dirent.h>, which MSVC does not
        # provide. This header-only MIT shim satisfies it; nothing else changes.
        Name    = 'dirent.h'
        Url     = "https://raw.githubusercontent.com/tronkko/dirent/$DirentVersion/include/dirent.h"
        Sha256  = '7383044a375d481ac8ad7ec2f43151263eca792f085001a8020cc590114a06a6'
        Unpacks = $null
    },
    @{
        Name    = 'abseil-cpp.tgz'
        Url     = 'https://paddle-model-ecology.bj.bcebos.com/paddlex/cpp/libs/abseil-cpp.tgz'
        Sha256  = 'ab51954baa519cb2c11fb461b0bdfd32836779ff3f3e50e5b845b0c80374ed6a'
        Unpacks = $null
    },
    @{
        Name    = 'clipper_ver6.4.2.tgz'
        Url     = 'https://paddle-model-ecology.bj.bcebos.com/paddlex/cpp/libs/clipper_ver6.4.2.tgz'
        Sha256  = '54ae753a24fcac5386416ea30ac1599cac60b00c27dab0d4f66696155b01e2be'
        Unpacks = $null
    },
    @{
        Name    = 'nlohmann.tgz'
        Url     = 'https://paddle-model-ecology.bj.bcebos.com/paddlex/cpp/libs/nlohmann.tgz'
        Sha256  = 'e04437150e0f302346e41501a2c6c918e87f57a4b605b8770601c9d8cf2b541a'
        Unpacks = $null
    }
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
        try {
            Invoke-WebRequest -Uri $Archive.Url -OutFile $target -UseBasicParsing
        } finally {
            $ProgressPreference = $previous
        }
    }

    $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Archive.Sha256) {
        throw "$($Archive.Name) SHA-256 mismatch: expected $($Archive.Sha256), got $actual"
    }
    Write-Host "Verified $($Archive.Name)"
    return $target
}

# Picks a Visual Studio instance carrying both the x64 toolset and the bundled
# CMake. `vswhere -latest` alone is not enough: a newer Build Tools instance can
# be installed without CMake, and its generator name would not match the
# "Visual Studio 17 2022" this script pins.
function Get-BuildToolchain {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    Assert-Path -Path $vswhere -What 'vswhere'

    $instances = & $vswhere -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -format json | ConvertFrom-Json
    if (-not $instances) { throw 'No Visual Studio instance with the C++ x64 toolset is installed' }

    $generators = @{ '17' = 'Visual Studio 17 2022' }
    foreach ($instance in $instances | Sort-Object installationVersion -Descending) {
        $major = ($instance.installationVersion -split '\.')[0]
        if (-not $generators.ContainsKey($major)) { continue }
        $vcvars = Join-Path $instance.installationPath 'VC\Auxiliary\Build\vcvars64.bat'
        $cmake = Join-Path $instance.installationPath `
            'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
        if ((Test-Path -LiteralPath $vcvars) -and (Test-Path -LiteralPath $cmake)) {
            return @{
                Root      = $instance.installationPath
                Vcvars    = $vcvars
                CMake     = $cmake
                Generator = $generators[$major]
            }
        }
    }
    throw 'No Visual Studio 2022 instance carries both vcvars64.bat and the bundled CMake'
}

Assert-Path -Path $SevenZip -What '7-Zip'
$toolchain = Get-BuildToolchain
Write-Host "Toolchain: $($toolchain.Generator) at $($toolchain.Root)"

$downloads = Join-Path $WorkRoot 'dl'
$compat = Join-Path $WorkRoot 'compat'
$buildDir = Join-Path $WorkRoot 'o'
$models = Join-Path $WorkRoot 'models'
$srcRoot = Join-Path $WorkRoot "PaddleOCR-$($PaddleOcrVersion.TrimStart('v'))"
$paddleLib = Join-Path $WorkRoot 'paddle_inference'
$opencvRoot = Join-Path $WorkRoot 'opencv'

if ($Clean) {
    Write-Host 'Clean build: discarding the source tree and build directory'
    Remove-Item -LiteralPath $srcRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $buildDir -Recurse -Force -ErrorAction SilentlyContinue
}
foreach ($dir in @($WorkRoot, $downloads, $compat, $models)) {
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

if ($paths.ContainsKey('dirent.h')) {
    Copy-Item -LiteralPath $paths['dirent.h'] -Destination (Join-Path $compat 'dirent.h') -Force
}
Assert-Path -Path (Join-Path $compat 'dirent.h') -What 'the dirent.h shim'

if ($paths.ContainsKey('paddleocr-src.tar.gz')) {
    & tar -xzf $paths['paddleocr-src.tar.gz'] -C $WorkRoot
    if ($LASTEXITCODE -ne 0) { throw 'Could not extract the PaddleOCR source' }
}
if ($paths.ContainsKey('paddle_inference.zip')) {
    & $SevenZip x -y "-o$paddleLib" $paths['paddle_inference.zip'] | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not extract Paddle Inference' }
}
if ($paths.ContainsKey('opencv-windows.exe')) {
    & $SevenZip x -y "-o$opencvRoot" $paths['opencv-windows.exe'] | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not extract OpenCV' }
}
$opencvDir = Join-Path $opencvRoot 'opencv\build'

$cppInfer = Join-Path $srcRoot 'deploy\cpp_infer'
$thirdParty = Join-Path $cppInfer 'third_party'
foreach ($package in @('abseil-cpp', 'clipper_ver6.4.2', 'nlohmann')) {
    $destination = Join-Path $thirdParty $package
    if (Test-Path -LiteralPath (Join-Path $destination '*')) { continue }
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    & tar -xzf $paths["${package}.tgz"] -C $destination
    if ($LASTEXITCODE -ne 0) { throw "Failed to extract $package" }
}

# Swap PaddleOCR's demo entry point for the Kizuna worker. The CMake target
# keeps its upstream name so the build directory stays incremental across
# reruns; the executable is renamed when it is staged below.
$workerSource = Join-Path $Payload 'worker\paddleocr_worker.cc'
Assert-Path -Path $workerSource -What 'the Kizuna PaddleOCR worker source'
Copy-Item -LiteralPath $workerSource -Destination (Join-Path $cppInfer 'kizuna_worker.cc') -Force

$cmakeLists = Join-Path $cppInfer 'CMakeLists.txt'
$cmakeText = Get-Content -LiteralPath $cmakeLists -Raw
$upstreamEntry = 'set(SRCS cli.cc )'
$kizunaEntry = 'set(SRCS kizuna_worker.cc )'
if ($cmakeText.Contains($upstreamEntry)) {
    Set-Content -LiteralPath $cmakeLists -Value $cmakeText.Replace($upstreamEntry, $kizunaEntry) `
        -NoNewline -Encoding utf8
    Write-Host 'Redirected cpp_infer to kizuna_worker.cc'
} elseif ($cmakeText.Contains($kizunaEntry)) {
    Write-Host 'cpp_infer already points at kizuna_worker.cc'
} else {
    throw "Could not find '$upstreamEntry' in $cmakeLists; the pinned PaddleOCR source changed"
}

# CMAKE_CXX_FLAGS replaces the MSVC defaults rather than adding to them, so the
# defaults have to be restated. Dropping /EHsc compiles the worker's try/catch
# without unwind semantics, and dropping /GR strips RTTI out from under Paddle.
$cxxFlags = "/DWIN32 /D_WINDOWS /W3 /GR /EHsc /I `"$compat`""
$buildScript = Join-Path $WorkRoot 'run-build.bat'
@"
@echo off
call "$($toolchain.Vcvars)" >nul || exit /b 1
cd /d "$cppInfer" || exit /b 1
"$($toolchain.CMake)" -S . -B "$buildDir" -G "$($toolchain.Generator)" -A x64 ^
  -DPADDLE_LIB="$paddleLib" -DOPENCV_DIR="$opencvDir" ^
  -DWITH_MKL=ON -DWITH_GPU=OFF -DWITH_STATIC_LIB=ON ^
  -DCMAKE_CXX_FLAGS="$cxxFlags" || exit /b 1
"$($toolchain.CMake)" --build "$buildDir" --config Release -j %NUMBER_OF_PROCESSORS% || exit /b 1
"@ | Set-Content -LiteralPath $buildScript -Encoding ascii

$timer = [System.Diagnostics.Stopwatch]::StartNew()
& cmd /c "`"$buildScript`""
if ($LASTEXITCODE -ne 0) { throw "cpp_infer build failed with exit code $LASTEXITCODE" }
$timer.Stop()
Write-Host "Compiled in $([math]::Round($timer.Elapsed.TotalSeconds)) s"

# Runtime closure: the worker imports paddle_inference, opencv_world, abseil_dll
# and polyclipping; paddle_inference in turn pulls common, phi, mklml,
# libiomp5md and mkldnn. opencv_world needs the VC CRT and mkldnn needs OpenMP.
$vcRedist = Get-ChildItem (Join-Path $toolchain.Root 'VC\Redist\MSVC') -Directory |
    Where-Object { $_.Name -match '^\d+\.' } | Sort-Object Name -Descending | Select-Object -First 1
$runtimeFiles = @(
    (Join-Path $buildDir 'Release\mklml.dll'),
    (Join-Path $buildDir 'Release\mkldnn.dll'),
    (Join-Path $buildDir 'Release\libiomp5md.dll'),
    (Join-Path $buildDir 'bin\Release\abseil_dll.dll'),
    (Join-Path $buildDir 'third_party\clipper_ver6.4.2\cpp\Release\polyclipping.dll'),
    (Join-Path $paddleLib 'paddle\lib\paddle_inference.dll'),
    (Join-Path $paddleLib 'paddle\lib\common.dll'),
    (Join-Path $paddleLib 'paddle\lib\phi.dll'),
    (Join-Path $opencvDir 'x64\vc16\bin\opencv_world4100.dll'),
    (Join-Path $vcRedist.FullName 'x64\Microsoft.VC143.CRT\msvcp140.dll'),
    (Join-Path $vcRedist.FullName 'x64\Microsoft.VC143.CRT\vcruntime140.dll'),
    (Join-Path $vcRedist.FullName 'x64\Microsoft.VC143.CRT\vcruntime140_1.dll'),
    (Join-Path $vcRedist.FullName 'x64\Microsoft.VC143.CRT\concrt140.dll'),
    (Join-Path $vcRedist.FullName 'x64\Microsoft.VC143.OpenMP\vcomp140.dll')
)
$workerBinary = Join-Path $buildDir 'Release\ppocr.exe'
Assert-Path -Path $workerBinary -What 'the built worker'

$binOut = Join-Path $Payload 'bin'
$modelsOut = Join-Path $Payload 'models'
Remove-Item -LiteralPath $binOut -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $modelsOut -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $binOut, $modelsOut | Out-Null

Copy-Item -LiteralPath $workerBinary -Destination (Join-Path $binOut 'paddleocr.exe') -Force
foreach ($file in $runtimeFiles) {
    Assert-Path -Path $file -What (Split-Path -Leaf $file)
    Copy-Item -LiteralPath $file -Destination $binOut -Force
}

foreach ($model in @('PP-OCRv5_mobile_det_infer', 'PP-OCRv5_mobile_rec_infer')) {
    if (-not (Test-Path -LiteralPath (Join-Path $models $model))) {
        & tar -xf $paths["$model.tar"] -C $models
        if ($LASTEXITCODE -ne 0) { throw "Could not extract $model" }
    }
}
Copy-Item -LiteralPath (Join-Path $models 'PP-OCRv5_mobile_det_infer') `
    -Destination (Join-Path $modelsOut 'det') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $models 'PP-OCRv5_mobile_rec_infer') `
    -Destination (Join-Path $modelsOut 'rec') -Recurse -Force

& (Join-Path $PSScriptRoot 'refresh-paddleocr-hashes.ps1')

Write-Host ''
Write-Host "Staged the worker, $($runtimeFiles.Count) runtime libraries and 2 models into $Payload"
Write-Host 'Now run ./scripts/verify-paddleocr-win-x64.ps1 before committing.'
