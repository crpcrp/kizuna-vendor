<#
.SYNOPSIS
    Rebuilds the Windows x64 PaddleOCR payload under paddleocr/.

.DESCRIPTION
    Downloads the pinned PaddleOCR source, Paddle Inference runtime, OpenCV
    package, and PP-OCRv5 Japanese models; verifies every archive by SHA-256;
    builds deploy/cpp_infer with MSVC; and stages the result into paddleocr/.

    Run from a clean checkout on a Windows x64 host with Visual Studio 2022
    Build Tools (C++ x64 workload) and 7-Zip installed. Then verify:

        git lfs pull
        ./scripts/verify-paddleocr-win-x64.ps1

.NOTES
    MSBuild's FileTracker fails once paths approach MAX_PATH, so the build runs
    under a short working root (C:\kzb by default) rather than in-tree.
#>
[CmdletBinding()]
param(
    [string]$WorkRoot = 'C:\kzb',
    [string]$SevenZip = "$env:ProgramFiles\7-Zip\7z.exe"
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

$Archives = @(
    @{
        Name   = 'paddleocr-src.tar.gz'
        Url    = "https://github.com/PaddlePaddle/PaddleOCR/archive/refs/tags/$PaddleOcrVersion.tar.gz"
        Sha256 = '8e5f1f9ba18c29621d38394b4f72925960640b315281391c3b3c86804f079a73'
    },
    @{
        Name   = 'paddle_inference.zip'
        Url    = "https://paddle-inference-lib.bj.bcebos.com/$PaddleInferenceVersion/cxx_c/Windows/CPU/x86-64_avx-mkl-vs2019/paddle_inference.zip"
        Sha256 = '23a2ea41abaedb7dfb928dc10baa72975d50b7a8ffe28f8e081a16a8977a95b2'
    },
    @{
        Name   = 'opencv-windows.exe'
        Url    = "https://github.com/opencv/opencv/releases/download/$OpenCvVersion/opencv-$OpenCvVersion-windows.exe"
        Sha256 = 'bff38466091c313dac21a0b73eea8278316a89c1d434c6f0b10697e087670168'
    },
    @{
        Name   = 'PP-OCRv5_mobile_det_infer.tar'
        Url    = 'https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv5_mobile_det_infer.tar'
        Sha256 = '50446e5d01ac2a73d5319c89513281f6578414c888c602f9af13f93feefffc58'
    },
    @{
        Name   = 'PP-OCRv5_mobile_rec_infer.tar'
        Url    = 'https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv5_mobile_rec_infer.tar'
        Sha256 = '566b9512b34e34a9f0db54d87b51fa5a0b9ed2cf1ab7e49728cc0b8b5a64f414'
    },
    @{
        # PaddleOCR 3.7.0's utility.cc includes <dirent.h>, which MSVC does not
        # provide. This header-only MIT shim satisfies it; nothing else changes.
        Name   = 'dirent.h'
        Url    = "https://raw.githubusercontent.com/tronkko/dirent/$DirentVersion/include/dirent.h"
        Sha256 = '7383044a375d481ac8ad7ec2f43151263eca792f085001a8020cc590114a06a6'
    }
)

function Assert-Tool {
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
        Invoke-WebRequest -Uri $Archive.Url -OutFile $target -UseBasicParsing
    }

    $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Archive.Sha256) {
        throw "$($Archive.Name) SHA-256 mismatch: expected $($Archive.Sha256), got $actual"
    }
    Write-Host "Verified $($Archive.Name)"
    return $target
}

Assert-Tool -Path $SevenZip -What '7-Zip'

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
Assert-Tool -Path $vswhere -What 'vswhere'
$vsRoot = & $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -latest -format value -property installationPath
if (-not $vsRoot) { throw 'Visual Studio with the C++ x64 toolset is required' }

$vcvars = Join-Path $vsRoot 'VC\Auxiliary\Build\vcvars64.bat'
$cmake = Join-Path $vsRoot 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
Assert-Tool -Path $vcvars -What 'vcvars64.bat'
Assert-Tool -Path $cmake -What 'cmake'

$downloads = Join-Path $WorkRoot 'dl'
$compat = Join-Path $WorkRoot 'compat'
$buildDir = Join-Path $WorkRoot 'o'
$stage = Join-Path $WorkRoot 'stage'
foreach ($dir in @($WorkRoot, $downloads, $compat, $stage)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$paths = @{}
foreach ($archive in $Archives) {
    $paths[$archive.Name] = Get-VerifiedArchive -Archive $archive -Destination $downloads
}

Copy-Item -LiteralPath $paths['dirent.h'] -Destination (Join-Path $compat 'dirent.h') -Force

$srcRoot = Join-Path $WorkRoot "PaddleOCR-$($PaddleOcrVersion.TrimStart('v'))"
if (-not (Test-Path -LiteralPath $srcRoot)) {
    & tar -xzf $paths['paddleocr-src.tar.gz'] -C $WorkRoot
}

$paddleLib = Join-Path $WorkRoot 'paddle_inference'
if (-not (Test-Path -LiteralPath $paddleLib)) {
    & $SevenZip x -y "-o$paddleLib" $paths['paddle_inference.zip'] | Out-Null
}

$opencvRoot = Join-Path $WorkRoot 'opencv'
if (-not (Test-Path -LiteralPath $opencvRoot)) {
    & $SevenZip x -y "-o$opencvRoot" $paths['opencv-windows.exe'] | Out-Null
}
$opencvDir = Join-Path $opencvRoot 'opencv\build'

$cppInfer = Join-Path $srcRoot 'deploy\cpp_infer'
$buildScript = Join-Path $WorkRoot 'run-build.bat'
@"
@echo off
call "$vcvars" >nul || exit /b 1
cd /d "$cppInfer" || exit /b 1
"$cmake" -S . -B "$buildDir" -G "Visual Studio 17 2022" -A x64 ^
  -DPADDLE_LIB="$paddleLib" -DOPENCV_DIR="$opencvDir" ^
  -DWITH_MKL=ON -DWITH_GPU=OFF -DWITH_STATIC_LIB=ON ^
  -DCMAKE_CXX_FLAGS="/I $compat" || exit /b 1
"$cmake" --build "$buildDir" --config Release -j %NUMBER_OF_PROCESSORS% || exit /b 1
"@ | Set-Content -LiteralPath $buildScript -Encoding ascii

& cmd /c "`"$buildScript`""
if ($LASTEXITCODE -ne 0) { throw "cpp_infer build failed with exit code $LASTEXITCODE" }

# Runtime closure: ppocr.exe imports paddle_inference, opencv_world, abseil_dll
# and polyclipping; paddle_inference in turn pulls common, phi, mklml,
# libiomp5md and mkldnn. opencv_world needs the VC CRT and mkldnn needs OpenMP.
$vcRedist = Get-ChildItem (Join-Path $vsRoot 'VC\Redist\MSVC') -Directory |
    Where-Object { $_.Name -match '^\d+\.' } | Sort-Object Name -Descending | Select-Object -First 1
$runtimeFiles = @(
    (Join-Path $buildDir 'Release\ppocr.exe'),
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

$binOut = Join-Path $Payload 'bin'
$modelsOut = Join-Path $Payload 'models'
Remove-Item -LiteralPath $binOut -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $modelsOut -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $binOut, $modelsOut | Out-Null

foreach ($file in $runtimeFiles) {
    Assert-Tool -Path $file -What (Split-Path -Leaf $file)
    Copy-Item -LiteralPath $file -Destination $binOut -Force
}

foreach ($model in @('PP-OCRv5_mobile_det_infer', 'PP-OCRv5_mobile_rec_infer')) {
    & tar -xf $paths["$model.tar"] -C $modelsOut
}

Write-Host ''
Write-Host "Staged $($runtimeFiles.Count) runtime files and 2 models into $Payload"
Write-Host 'Regenerate SHA256SUMS.txt and manifest.json before committing.'
