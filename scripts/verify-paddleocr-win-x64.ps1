<#
.SYNOPSIS
    Verifies the Windows x64 PaddleOCR payload under paddleocr/.

.DESCRIPTION
    Checks every payload file against SHA256SUMS.txt, starts the persistent
    worker, sends two Japanese recognition requests through the Kizuna JSONL
    protocol, and checks that the second request completes within two seconds.
#>
[CmdletBinding()]
param(
    [int]$MaxWarmRecognitionMs = 2000
)

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

function Wait-Line {
    param(
        [System.IO.StreamReader]$Reader,
        [int]$TimeoutMs,
        [string]$What
    )
    $task = $Reader.ReadLineAsync()
    if (-not $task.Wait($TimeoutMs)) { throw "Timed out waiting for $What" }
    if ($null -eq $task.Result) { throw "Worker exited before $What" }
    return $task.Result
}

function Quote-Argument {
    param([string]$Value)
    return '"' + ($Value -replace '"', '\"') + '"'
}

Write-Host ''
Write-Host '== Persistent worker =='
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) 'kizuna-paddleocr-fixture.png'
$fixtureText = -join @(
    [char]0x4eca, [char]0x65e5, [char]0x306f, [char]0x3044, [char]0x3044,
    [char]0x5929, [char]0x6c17, [char]0x3067, [char]0x3059, [char]0x306d,
    [char]0x3002
)

Add-Type -AssemblyName System.Drawing
$bitmap = New-Object System.Drawing.Bitmap 900, 130
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$font = New-Object System.Drawing.Font('Yu Gothic UI', 40)
try {
    $graphics.Clear([System.Drawing.Color]::White)
    $graphics.TextRenderingHint = 'AntiAliasGridFit'
    $graphics.DrawString($fixtureText, $font, [System.Drawing.Brushes]::Black, 30, 30)
    $bitmap.Save($fixture, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $font.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}

$worker = Join-Path $Payload 'bin\paddleocr.exe'
$detModel = Join-Path $Payload 'models\det'
$recModel = Join-Path $Payload 'models\rec'
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $worker
$startInfo.Arguments = @(
    '--protocol-version', '1', '--lang', 'japan',
    '--det-model', (Quote-Argument $detModel),
    '--rec-model', (Quote-Argument $recModel)
) -join ' '
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$utf8 = New-Object System.Text.UTF8Encoding($false)
$startInfo.StandardOutputEncoding = $utf8
$startInfo.StandardErrorEncoding = $utf8

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $startInfo
if (-not $process.Start()) { throw 'Could not start paddleocr.exe' }
$stderrTask = $process.StandardError.ReadToEndAsync()

try {
    $ready = (Wait-Line $process.StandardOutput 15000 'the ready handshake') | ConvertFrom-Json
    if ($ready.version -ne 1 -or $ready.type -ne 'ready') {
        throw 'Worker returned an invalid ready handshake'
    }

    $imageBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($fixture))
    $times = @()
    $lastResult = $null
    foreach ($requestId in 1..2) {
        $request = @{
            version = 1
            type = 'recognize'
            requestId = $requestId
            sessionId = 1
            captureId = $requestId
            imageSize = @{ width = 900; height = 130 }
            imageBase64 = $imageBase64
        } | ConvertTo-Json -Compress

        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $process.StandardInput.WriteLine($request)
        $process.StandardInput.Flush()
        $lastResult = (Wait-Line $process.StandardOutput 30000 "result $requestId") | ConvertFrom-Json
        $timer.Stop()
        $times += $timer.ElapsedMilliseconds
        if ($lastResult.version -ne 1 -or $lastResult.type -ne 'result' -or
            $lastResult.requestId -ne $requestId) {
            throw "Worker returned an invalid result for request $requestId"
        }
    }

    $recognized = ($lastResult.regions | ForEach-Object { $_.text }) -join ''
    if ($recognized -notmatch [regex]::Escape($fixtureText.Substring(0, 5))) {
        Write-Host "Did not recognize the Japanese fixture: $recognized"
        $failures++
    } else {
        Write-Host 'Recognized the Japanese fixture twice in one process'
    }
    Write-Host "First request:  $($times[0]) ms"
    Write-Host "Second request: $($times[1]) ms"
    if ($times[1] -gt $MaxWarmRecognitionMs) {
        Write-Host "Warm recognition exceeded ${MaxWarmRecognitionMs} ms"
        $failures++
    }
} finally {
    $process.StandardInput.Close()
    if (-not $process.WaitForExit(2000)) { $process.Kill() }
    $stderr = $stderrTask.Result
    if ($stderr) { Write-Host "Worker stderr:`n$stderr" }
    $process.Dispose()
    Remove-Item -LiteralPath $fixture -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($failures -gt 0) {
    throw "$failures verification problem(s)"
}
Write-Host 'Payload verified.'
