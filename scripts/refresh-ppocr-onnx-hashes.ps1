<#
.SYNOPSIS
    Refreshes hashes for the staged Windows x64 PP-OCR ONNX payload.

.DESCRIPTION
    Hashes every file under ppocr/, rewrites that block in SHA256SUMS.txt, and
    updates the files recorded by the win32-x64 ppocr manifest component.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $RepoRoot 'manifest.json'
$sumsPath = Join-Path $RepoRoot 'SHA256SUMS.txt'
$payload = Join-Path $RepoRoot 'ppocr'
if (-not (Test-Path -LiteralPath (Join-Path $payload 'bin\ppocr.exe'))) {
    throw "No staged ppocr payload at $payload; run build-ppocr-onnx-win-x64.ps1 first"
}

$staged = [ordered]@{}
foreach ($file in Get-ChildItem -LiteralPath $payload -File -Recurse | Sort-Object FullName) {
    $relative = $file.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/')
    $staged[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
Write-Host "Hashed $($staged.Count) staged ppocr files"

$existing = @(Get-Content -LiteralPath $sumsPath | Where-Object { $_ -ne '' -and
        $_ -notmatch '^[0-9a-f]{64}\s+ppocr/' })
$paths = [string[]]@($staged.Keys)
[array]::Sort($paths, [StringComparer]::Ordinal)
$lines = @($paths | ForEach-Object { "$($staged[$_])  $_" })
# The block keeps its place between the Windows payloads and the Linux tree.
# Anchored on the first linux-x64 line: the retired paddleocr block this used to
# insert before no longer exists, and an absent anchor would append instead.
$insertAt = 0
while ($insertAt -lt $existing.Count -and
        $existing[$insertAt] -notmatch '^[0-9a-f]{64}\s+linux-x64/') {
    $insertAt++
}
$before = @($existing | Select-Object -First $insertAt)
$after = @($existing | Select-Object -Skip $insertAt)
[IO.File]::WriteAllText($sumsPath, ((@($before) + $lines + @($after)) -join "`n") + "`n",
    [Text.ASCIIEncoding]::new())

$manifest = Get-Content -LiteralPath $manifestPath -Raw
$parsed = $manifest | ConvertFrom-Json
$component = @($parsed.payloads | Where-Object {
        $_.platform -eq 'win32' -and $_.architecture -eq 'x64'
    } | ForEach-Object { $_.components } | Where-Object { $_.name -eq 'ppocr' })
if ($component.Count -ne 1) { throw 'manifest.json must contain one win32-x64 ppocr component' }

$recorded = [Collections.Generic.HashSet[string]]::new()
foreach ($entry in @($component.files)) {
    if (-not $staged.Contains($entry.path)) {
        throw "manifest.json records $($entry.path), which the build did not stage"
    }
    $pattern = '(?s)("path"\s*:\s*"' + [regex]::Escape($entry.path) +
        '"\s*,\s*"sha256"\s*:\s*")[^"]*(")'
    $replacement = "`${1}$($staged[$entry.path])`${2}"
    $updated = [regex]::Replace($manifest, $pattern, $replacement)
    if ($updated -eq $manifest -and $entry.sha256 -ne $staged[$entry.path]) {
        throw "Could not rewrite the manifest hash for $($entry.path)"
    }
    $manifest = $updated
    [void]$recorded.Add($entry.path)
}
foreach ($licensePath in @($component.licenseFiles)) {
    if (-not $staged.Contains($licensePath)) { throw "Missing manifest licence $licensePath" }
    [void]$recorded.Add($licensePath)
}

$sourcePatterns = @('ppocr/worker/*', 'ppocr/patches/*', 'ppocr/tools/*')
$sourceFiles = @('ppocr/LICENSING.md', 'ppocr/README.md')
$unrecorded = @($staged.Keys | Where-Object {
    $path = $_
    -not $recorded.Contains($path) -and
    $path -notin $sourceFiles -and
    -not @($sourcePatterns | Where-Object { $path -like $_ }).Count
})
if ($unrecorded) { throw "manifest.json records no entry for: $($unrecorded -join ', ')" }

[IO.File]::WriteAllText($manifestPath, $manifest, [Text.UTF8Encoding]::new($false))
if ($manifest.Contains('BUILD_OUTPUT_PENDING')) {
    throw 'manifest.json still carries a BUILD_OUTPUT_PENDING placeholder'
}
Write-Host "Refreshed $($component.files.Count) manifest hashes and SHA256SUMS.txt"
