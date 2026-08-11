<#
.SYNOPSIS
    Verifies the Windows x64 PaddleOCR payload under paddleocr/.

.DESCRIPTION
    Checks every payload file against SHA256SUMS.txt, starts the persistent
    worker, and drives it through the Kizuna JSONL protocol with a committed
    1920x1080 capture that stands in for a game screen. Reports the cold start
    and the warm per-request latency, and fails if recognition is wrong or the
    warm path exceeds -MaxWarmRecognitionMs.

    The fixture is a committed PNG rather than text drawn at run time: rendering
    it locally would make the result depend on which Japanese fonts happen to be
    installed, and a hosted runner has none of them.

.PARAMETER MaxWarmRecognitionMs
    Warm-path budget. The default reflects a developer desktop. Hosted runners
    have a quarter of the cores and are several times slower, so CI should pass
    a looser ceiling; the measured numbers are always printed either way.
#>
[CmdletBinding()]
param(
    [int]$MaxWarmRecognitionMs = 2500,
    [int]$Repetitions = 4
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

# A payload whose bytes are wrong will not produce a meaningful latency number.
if ($failures -gt 0) { throw "$failures checksum problem(s); not running the worker" }

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
$fixture = Join-Path $PSScriptRoot 'testdata\game-capture-1080p.png'
if (-not (Test-Path -LiteralPath $fixture)) { throw "Missing the OCR fixture at $fixture" }
# The lines drawn into the fixture, in top-to-bottom order.
$expectedLines = @(
    -join @([char]0x4eca, [char]0x65e5, [char]0x306f, [char]0x3044, [char]0x3044,
            [char]0x5929, [char]0x6c17, [char]0x3067, [char]0x3059, [char]0x306d, [char]0x3002)
    -join @([char]0x653b, [char]0x6483, [char]0x529b, [char]0x304c, [char]0x4e0a,
            [char]0x304c, [char]0x3063, [char]0x305f, [char]0xff01)
    -join @([char]0x30ec, [char]0x30d9, [char]0x30eb, [char]0x30a2, [char]0x30c3,
            [char]0x30d7, [char]0x3057, [char]0x307e, [char]0x3057, [char]0x305f, [char]0x3002)
    -join @([char]0x6b21, [char]0x306e, [char]0x753a, [char]0x3078, [char]0x5411,
            [char]0x304b, [char]0x3044, [char]0x307e, [char]0x3057, [char]0x3087, [char]0x3046, [char]0x3002)
    -join @([char]0x4ed8, [char]0x8fd1, [char]0x306e, [char]0x5b9d, [char]0x7bb1,
            [char]0x3092, [char]0x958b, [char]0x3051, [char]0x308b, [char]0x3002)
)

$worker = Join-Path $Payload 'bin\paddleocr.exe'
$detModel = Join-Path $Payload 'models\det'
$recModel = Join-Path $Payload 'models\rec'
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $worker
# Exactly the argument list Kizuna's buildPaddleOcrWorkerArgs produces, so this
# exercises the shipped defaults rather than a tuned configuration.
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
$coldTimer = [System.Diagnostics.Stopwatch]::StartNew()
if (-not $process.Start()) { throw 'Could not start paddleocr.exe' }
$stderrTask = $process.StandardError.ReadToEndAsync()

try {
    $ready = (Wait-Line $process.StandardOutput 60000 'the ready handshake') | ConvertFrom-Json
    $coldTimer.Stop()
    if ($ready.version -ne 1 -or $ready.type -ne 'ready') {
        throw 'Worker returned an invalid ready handshake'
    }
    Write-Host "Cold start (launch to ready, models loaded and warmed): $($coldTimer.ElapsedMilliseconds) ms"

    $imageBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($fixture))
    $times = @()
    $lastResult = $null
    foreach ($requestId in 1..$Repetitions) {
        $request = @{
            version = 1
            type = 'recognize'
            requestId = $requestId
            sessionId = 1
            captureId = $requestId
            imageSize = @{ width = 1920; height = 1080 }
            imageBase64 = $imageBase64
        } | ConvertTo-Json -Compress

        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $process.StandardInput.WriteLine($request)
        $process.StandardInput.Flush()
        $lastResult = (Wait-Line $process.StandardOutput 120000 "result $requestId") | ConvertFrom-Json
        $timer.Stop()
        $times += $timer.ElapsedMilliseconds
        if ($lastResult.version -ne 1 -or $lastResult.type -ne 'result' -or
            $lastResult.requestId -ne $requestId) {
            throw "Worker returned an invalid result for request $requestId"
        }
    }

    $recognized = ($lastResult.regions | ForEach-Object { $_.text }) -join ''
    $missing = @($expectedLines | Where-Object { $recognized -notlike "*$_*" })
    if ($missing.Count -gt 0) {
        Write-Host "Recognized: $recognized"
        foreach ($line in $missing) { Write-Host "MISSING LINE  $line" }
        $failures++
    } else {
        Write-Host "Recognized all $($expectedLines.Count) Japanese lines across $Repetitions requests in one process"
    }

    # The first request pays one-off allocation the warm path does not.
    $warm = @($times | Select-Object -Skip 1)
    $warmMedian = (@($warm | Sort-Object))[[int]([math]::Floor($warm.Count / 2))]
    Write-Host "First request: $($times[0]) ms"
    Write-Host "Warm requests: $($warm -join ', ') ms (median $warmMedian ms)"
    if ($warmMedian -gt $MaxWarmRecognitionMs) {
        Write-Host "Warm recognition median exceeded ${MaxWarmRecognitionMs} ms"
        $failures++
    }
} finally {
    $process.StandardInput.Close()
    if (-not $process.WaitForExit(2000)) { $process.Kill() }
    $stderr = $stderrTask.Result
    # Paddle logs a deprecation notice about the ONEDNN API on every start.
    $noise = $stderr -split "`r?`n" | Where-Object {
        $_ -ne '' -and $_ -notmatch 'InitGoogleLogging|api is deprecated since version'
    }
    if ($noise) { Write-Host "Worker stderr:`n$($noise -join "`n")" }
    $process.Dispose()
}

Write-Host ''
if ($failures -gt 0) {
    throw "$failures verification problem(s)"
}
Write-Host 'Payload verified.'
