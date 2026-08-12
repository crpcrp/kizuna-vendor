<#
.SYNOPSIS
    Verifies the Windows x64 PP-OCR ONNX Runtime worker.

.DESCRIPTION
    Starts the worker that scripts/build-ppocr-onnx-win-x64.ps1 leaves in its
    build tree and drives it through the Kizuna JSONL protocol with a committed
    1920x1080 capture that stands in for a game screen. Checks protocol version
    1 parity point by point, reports the startup time and the warm per-request
    latency, and fails if recognition is wrong, the protocol is broken or the
    warm path exceeds -MaxWarmRecognitionMs.

    Unlike verify-paddleocr-win-x64.ps1 this checks no hashes and no manifest:
    nothing is staged in ppocr/ yet, so there is nothing to check them against.
    Those checks arrive with the payload.

    The fixture is a committed PNG rather than text drawn at run time: rendering
    it locally would make the result depend on which Japanese fonts happen to be
    installed.

.PARAMETER Runtime
    The directory the build script staged, holding bin\ppocr.exe,
    bin\onnxruntime.dll and models\.

.PARAMETER MaxWarmRecognitionMs
    Warm-path budget. The default is generous against the ~85 ms a sixteen-core
    developer desktop measures, so that it catches a regression to something
    Paddle-shaped rather than ordinary variation on a slower machine. The
    measured numbers are always printed either way.

.PARAMETER OverlayPath
    Where to write the fixture with the returned quadrilaterals drawn over it,
    so the coordinates can be eyeballed rather than trusted. Defaults to
    fixture-quads.png beside the worker.
#>
[CmdletBinding()]
param(
    [string]$Runtime = 'C:\kizuna\build-tools\ppocr\out',
    [int]$MaxWarmRecognitionMs = 400,
    [int]$Repetitions = 12,
    [string]$OverlayPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$failures = 0

Write-Host '== Worker tree =='
$worker = Join-Path $Runtime 'bin\ppocr.exe'
$detModel = Join-Path $Runtime 'models\ch_PP-OCRv5_det_mobile.onnx'
$recModel = Join-Path $Runtime 'models\ch_PP-OCRv5_rec_mobile.onnx'
$keys = Join-Path $Runtime 'models\keys.txt'
foreach ($required in @($worker, (Join-Path $Runtime 'bin\onnxruntime.dll'),
        $detModel, $recModel, $keys)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Missing $required; run scripts/build-ppocr-onnx-win-x64.ps1 first"
    }
}
$total = (Get-ChildItem -LiteralPath $Runtime -Recurse -File |
    Measure-Object -Property Length -Sum).Sum
Write-Host ("Worker tree is {0:N1} MB" -f ($total / 1MB))

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

# Every line the worker writes to stdout has to be a protocol frame; stdout
# carries nothing else. Parsing each one is how that gets checked rather than
# assumed.
function Read-Frame {
    param(
        [System.IO.StreamReader]$Reader,
        [int]$TimeoutMs,
        [string]$What
    )
    $line = Wait-Line -Reader $Reader -TimeoutMs $TimeoutMs -What $What
    try {
        $frame = $line | ConvertFrom-Json
    } catch {
        throw "Non-protocol output on stdout while waiting for ${What}: $line"
    }
    if ($frame.version -ne 1) { throw "Frame for $What is not protocol version 1: $line" }
    return $frame
}

function Quote-Argument {
    param([string]$Value)
    return '"' + ($Value -replace '"', '\"') + '"'
}

$requiredArguments = @(
    '--protocol-version', '1', '--lang', 'japan',
    '--det-model', (Quote-Argument $detModel),
    '--rec-model', (Quote-Argument $recModel),
    '--keys', (Quote-Argument $keys)
)

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

$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $worker
$startInfo.Arguments = @(
    $requiredArguments
    # This includes Kizuna's current argument plus every compatibility-only
    # Paddle option. Functional tuning options use their defaults here.
    '--det-side-len', '960', '--det-limit-type', 'max',
    '--det-thresh', '0.3', '--det-box-thresh', '0.6',
    '--det-unclip-ratio', '1.5', '--rec-score-thresh', '0',
    '--rec-batch-size', '8', '--rec-width', '320',
    '--mkldnn-cache', '512', '--det-model-name', 'X', '--rec-model-name', 'Y'
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
if (-not $process.Start()) { throw 'Could not start ppocr.exe' }
$stderrTask = $process.StandardError.ReadToEndAsync()

$lastResult = $null
try {
    $ready = Read-Frame $process.StandardOutput 60000 'the ready handshake'
    $coldTimer.Stop()
    if ($ready.type -ne 'ready') { throw 'Worker returned an invalid ready handshake' }
    # Not comparable to a recognition time: the warm-up frame is a 384x96 strip
    # with one ASCII word, so this is model load plus a near-empty inference,
    # not the cost of a real capture.
    Write-Host "Startup (launch to ready, models loaded and warmed): $($coldTimer.ElapsedMilliseconds) ms"

    $imageBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($fixture))
    $times = @()
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
        $lastResult = Read-Frame $process.StandardOutput 120000 "result $requestId"
        $timer.Stop()
        $times += $timer.ElapsedMilliseconds
        if ($lastResult.type -ne 'result' -or $lastResult.requestId -ne $requestId) {
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
    $sorted = @($warm | Sort-Object)
    $warmMedian = $sorted[[int]([math]::Floor($sorted.Count / 2))]
    $warm95 = $sorted[[int]([math]::Ceiling(0.95 * $sorted.Count)) - 1]
    Write-Host "First request: $($times[0]) ms"
    Write-Host "Warm requests: $($warm -join ', ') ms (p50 $warmMedian ms, p95 $warm95 ms)"
    if ($warmMedian -gt $MaxWarmRecognitionMs) {
        Write-Host "Warm recognition median exceeded ${MaxWarmRecognitionMs} ms"
        $failures++
    }

    Write-Host ''
    Write-Host '== Regions =='
    # Quads are in source pixels, four points, clockwise from the top-left, and
    # the regions arrive in reading order. A region that lands outside the frame
    # or out of order would still look plausible in the text alone.
    $previousTop = -1
    foreach ($region in $lastResult.regions) {
        if ($region.quad.Count -ne 4) {
            Write-Host "BAD QUAD  $($region.text) has $($region.quad.Count) points"
            $failures++
            continue
        }
        $xs = @($region.quad | ForEach-Object { $_[0] })
        $ys = @($region.quad | ForEach-Object { $_[1] })
        $left = ($xs | Measure-Object -Minimum).Minimum
        $right = ($xs | Measure-Object -Maximum).Maximum
        $top = ($ys | Measure-Object -Minimum).Minimum
        $bottom = ($ys | Measure-Object -Maximum).Maximum
        if ($left -lt 0 -or $top -lt 0 -or $right -ge 1920 -or $bottom -ge 1080 -or
            $right -le $left -or $bottom -le $top) {
            Write-Host "OFF FRAME $($region.text) [$left,$top,$right,$bottom]"
            $failures++
        }
        if ($top -lt $previousTop) {
            Write-Host "OUT OF ORDER  $($region.text) starts above the region before it"
            $failures++
        }
        $previousTop = $top
        if ($region.confidence -lt 0 -or $region.confidence -gt 1) {
            Write-Host "BAD CONFIDENCE  $($region.text) = $($region.confidence)"
            $failures++
        }
        Write-Host ("  {0,-14:N6}  {1,4},{2,4}  {3,4}x{4,-4}  {5}" -f `
            $region.confidence, $left, $top, ($right - $left), ($bottom - $top), $region.text)
    }

    Write-Host ''
    Write-Host '== Malformed requests =='
    # Each of these has to come back as an error and leave the worker able to
    # answer the next capture.
    $malformed = @(
        @{ Name = 'a truncated line'; Line = '{"version":1,"type":"recognize"' },
        @{ Name = 'a line that is not JSON'; Line = 'not json at all' },
        @{ Name = 'a leading-zero JSON number'; Line = '{"version":01,"type":"recognize","requestId":97,"imageBase64":""}' },
        @{ Name = 'an incomplete JSON exponent'; Line = '{"version":1e,"type":"recognize","requestId":96,"imageBase64":""}' },
        @{ Name = 'an unusable image'; Line = '{"version":1,"type":"recognize","requestId":99,"imageBase64":"@@@"}' },
        @{ Name = 'the wrong protocol version'; Line = '{"version":2,"type":"recognize","requestId":98,"imageBase64":""}' }
    )
    foreach ($case in $malformed) {
        $process.StandardInput.WriteLine($case.Line)
        $process.StandardInput.Flush()
        $frame = Read-Frame $process.StandardOutput 30000 "the error for $($case.Name)"
        if ($frame.type -ne 'error') {
            Write-Host "NOT AN ERROR  $($case.Name) returned $($frame.type)"
            $failures++
        } else {
            Write-Host "  $($case.Name) -> error"
        }
    }

    $request = @{
        version = 1; type = 'recognize'; requestId = 1000
        imageBase64 = $imageBase64
    } | ConvertTo-Json -Compress
    $process.StandardInput.WriteLine($request)
    $process.StandardInput.Flush()
    $survivor = Read-Frame $process.StandardOutput 120000 'the result after the malformed lines'
    if ($survivor.type -ne 'result' -or $survivor.requestId -ne 1000 -or
        $survivor.regions.Count -ne $lastResult.regions.Count) {
        Write-Host 'DID NOT RECOVER  the worker did not answer normally after a malformed line'
        $failures++
    } else {
        Write-Host '  the worker answered the next capture normally'
    }
} finally {
    $process.StandardInput.Close()
    if (-not $process.WaitForExit(5000)) { $process.Kill() }
    # Whatever is left on stdout after the last answered request is output the
    # protocol did not ask for.
    $trailing = $process.StandardOutput.ReadToEnd()
    if ($trailing.Trim() -ne '') {
        Write-Host "UNEXPECTED STDOUT  $trailing"
        $failures++
    }
    $stderr = $stderrTask.Result
    if ($stderr) { Write-Host "Worker stderr:`n$($stderr.TrimEnd())" }
    foreach ($ignored in @('--mkldnn-cache', '--det-model-name', '--rec-model-name')) {
        if ($stderr -notlike "*note: $ignored is accepted for compatibility and ignored*") {
            Write-Host "MISSING NOTE  $ignored"
            $failures++
        }
    }
    $process.Dispose()
}

Write-Host ''
Write-Host '== Invalid worker options =='
$invalidOptions = @(
    @('--det-side-len', '0'),
    @('--det-side-len', '4097'),
    @('--det-limit-type', 'min'),
    @('--det-thresh', '1.1'),
    @('--det-box-thresh', '-0.1'),
    @('--det-unclip-ratio', '0'),
    @('--rec-score-thresh', 'nan'),
    @('--cpu-threads', '0'),
    @('--rec-batch-size', '0'),
    @('--rec-width', '0')
)
foreach ($invalid in $invalidOptions) {
    $badStart = New-Object System.Diagnostics.ProcessStartInfo
    $badStart.FileName = $worker
    $badStart.Arguments = @($requiredArguments + $invalid) -join ' '
    $badStart.UseShellExecute = $false
    $badStart.CreateNoWindow = $true
    $badStart.RedirectStandardOutput = $true
    $badStart.RedirectStandardError = $true
    $badProcess = New-Object System.Diagnostics.Process
    $badProcess.StartInfo = $badStart
    if (-not $badProcess.Start()) { throw 'Could not start ppocr.exe' }
    $badStdout = $badProcess.StandardOutput.ReadToEndAsync()
    $badStderr = $badProcess.StandardError.ReadToEndAsync()
    if (-not $badProcess.WaitForExit(5000)) {
        $badProcess.Kill()
        throw "Worker did not reject $($invalid -join ' ') at startup"
    }
    $badFrame = $badStdout.Result | ConvertFrom-Json
    if ($badProcess.ExitCode -eq 0 -or $badFrame.type -ne 'error' -or
        $badStderr.Result -notlike '*invalid worker options*') {
        Write-Host "NOT REJECTED  $($invalid -join ' ')"
        $failures++
    } else {
        Write-Host "  $($invalid -join ' ') -> exit $($badProcess.ExitCode)"
    }
    $badProcess.Dispose()
}

# The coordinates are the one part of the protocol that cannot be checked by
# reading the JSON: they are only right if they sit on the text.
if (-not $OverlayPath) { $OverlayPath = Join-Path $Runtime 'fixture-quads.png' }
Write-Host ''
Write-Host '== Overlay =='
Add-Type -AssemblyName System.Drawing
$source = [System.Drawing.Image]::FromFile($fixture)
try {
    $canvas = New-Object System.Drawing.Bitmap $source
} finally {
    $source.Dispose()
}
try {
    $graphics = [System.Drawing.Graphics]::FromImage($canvas)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Magenta), 3
    try {
        foreach ($region in $lastResult.regions) {
            if ($region.quad.Count -ne 4) { continue }
            $points = @($region.quad | ForEach-Object {
                New-Object System.Drawing.Point ([int]$_[0]), ([int]$_[1])
            })
            $graphics.DrawPolygon($pen, $points)
        }
    } finally {
        $pen.Dispose()
        $graphics.Dispose()
    }
    $canvas.Save($OverlayPath, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $canvas.Dispose()
}
Write-Host "Wrote $OverlayPath"

Write-Host ''
if ($failures -gt 0) {
    throw "$failures verification problem(s)"
}
Write-Host 'Worker verified.'
