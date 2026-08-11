<#
.SYNOPSIS
    Verifies the Windows x64 PaddleOCR payload under paddleocr/.

.DESCRIPTION
    Checks every payload file against SHA256SUMS.txt, confirms the runtime
    dependency closure resolves, and runs one Japanese recognition against a
    generated fixture. Run after `git lfs pull` on a Windows x64 host.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Payload = Join-Path $RepoRoot 'paddleocr'
$failures = 0

Write-Host '== Checksums =='
$expected = @{}
foreach ($line in Get-Content (Join-Path $RepoRoot 'SHA256SUMS.txt')) {
    if ($line -match '^([0-9a-f]{64})\s+(paddleocr/.+)$') {
        $expected[$Matches[2]] = $Matches[1]
    }
}
if ($expected.Count -eq 0) { throw 'SHA256SUMS.txt lists no paddleocr files' }

foreach ($relative in $expected.Keys | Sort-Object) {
    $full = Join-Path $RepoRoot ($relative -replace '/', '\')
    if (-not (Test-Path -LiteralPath $full)) {
        Write-Host "MISSING  $relative"
        $failures++
        continue
    }
    $actual = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected[$relative]) {
        Write-Host "MISMATCH $relative"
        $failures++
    }
}
Write-Host "Checked $($expected.Count) files, $failures problem(s)"

Write-Host ''
Write-Host '== Recognition =='
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) 'kizuna-paddleocr-fixture.png'
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap 900, 130
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::White)
$g.TextRenderingHint = 'AntiAliasGridFit'
$font = New-Object System.Drawing.Font('Yu Gothic UI', 40)
$g.DrawString('今日はいい天気ですね。', $font, [System.Drawing.Brushes]::Black, 30, 30)
$g.Dispose()
$bmp.Save($fixture, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

$env:GLOG_minloglevel = '3'
# ppocr writes result files next to its working directory unless told
# otherwise; keep them out of the payload.
$savePath = Join-Path ([System.IO.Path]::GetTempPath()) 'kizuna-paddleocr-verify'
Push-Location (Join-Path $Payload 'bin')
try {
    $output = & .\ppocr.exe ocr --input $fixture --lang japan --ocr_version PP-OCRv5 `
        --text_detection_model_dir ..\models\PP-OCRv5_server_det_infer `
        --text_detection_model_name PP-OCRv5_server_det `
        --text_recognition_model_dir ..\models\PP-OCRv5_server_rec_infer `
        --text_recognition_model_name PP-OCRv5_server_rec `
        --use_doc_orientation_classify false --use_doc_unwarping false `
        --use_textline_orientation false --save_path $savePath 2>&1 | Out-String
} finally {
    Pop-Location
    Remove-Item -LiteralPath $fixture -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $savePath -Recurse -Force -ErrorAction SilentlyContinue
}

if ($output -match '今日はいい天気ですね') {
    Write-Host 'Recognized the Japanese fixture'
} else {
    Write-Host 'Did not recognize the Japanese fixture. Engine output:'
    Write-Host $output
    $failures++
}

if ($output -match 'Mkldnn is not available') {
    Write-Host 'Note: oneDNN is off. PaddleOCR gates it on an Intel CPU brand string.'
}

Write-Host ''
if ($failures -gt 0) {
    throw "$failures verification problem(s)"
}
Write-Host 'Payload verified.'
