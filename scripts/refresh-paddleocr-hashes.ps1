<#
.SYNOPSIS
    Rewrites the recorded SHA-256 hashes for the staged paddleocr/ payload.

.DESCRIPTION
    Recomputes every paddleocr/ line in SHA256SUMS.txt and every "sha256" value
    the win32 paddleocr component records in manifest.json, so both files match
    whatever build-paddleocr-win-x64.ps1 just staged.

    manifest.json is edited as text rather than round-tripped through
    ConvertTo-Json: Windows PowerShell 5.1 reflows and re-escapes the document,
    which would bury the real change in noise.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $RepoRoot 'manifest.json'
$sumsPath = Join-Path $RepoRoot 'SHA256SUMS.txt'
$payload = Join-Path $RepoRoot 'paddleocr'

if (-not (Test-Path -LiteralPath $payload)) { throw "No staged payload at $payload" }

# Hash everything currently staged, keyed by repo-relative forward-slash path.
$staged = [ordered]@{}
foreach ($file in Get-ChildItem -LiteralPath $payload -File -Recurse | Sort-Object FullName) {
    $relative = $file.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/')
    $staged[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
Write-Host "Hashed $($staged.Count) staged paddleocr files"

# SHA256SUMS.txt: rewrite the paddleocr block in place. The surrounding lines
# keep their order deliberately -- the Linux payload is appended after the
# Windows one rather than interleaved, and a global re-sort would rewrite the
# whole file every time this runs.
$existing = @(Get-Content -LiteralPath $sumsPath | Where-Object { $_ -ne '' })
$isPaddle = { param($line) $line -match '^[0-9a-f]{64}\s+paddleocr/' }
# Ordered by path, ordinally: the existing file orders "LICENSE.P*" before
# "LICENSE.d*", and PowerShell's culture-aware default would reshuffle it.
$paddlePaths = [string[]]@($staged.Keys)
[array]::Sort($paddlePaths, [StringComparer]::Ordinal)
$paddleLines = foreach ($relative in $paddlePaths) { "$($staged[$relative])  $relative" }

$firstPaddle = 0
while ($firstPaddle -lt $existing.Count -and -not (& $isPaddle $existing[$firstPaddle])) {
    $firstPaddle++
}
$before = @($existing[0..($firstPaddle - 1)] | Where-Object { $firstPaddle -gt 0 })
$after = @($existing | Select-Object -Skip $firstPaddle | Where-Object { -not (& $isPaddle $_) })
@($before) + @($paddleLines) + @($after) |
    Set-Content -LiteralPath $sumsPath -Encoding ascii

# manifest.json: update the sha256 that follows each recorded paddleocr path.
$manifest = Get-Content -LiteralPath $manifestPath -Raw
$component = (Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).payloads |
    Where-Object { $_.platform -eq 'win32' } |
    ForEach-Object { $_.components } |
    Where-Object { $_.name -eq 'paddleocr' }
if (-not $component) { throw 'manifest.json has no win32 paddleocr component' }

$updated = 0
foreach ($entry in $component.files) {
    if (-not $staged.Contains($entry.path)) {
        throw "manifest.json records $($entry.path), which the build did not stage"
    }
    $pattern = '(?s)("path"\s*:\s*"' + [regex]::Escape($entry.path) + '"\s*,\s*"sha256"\s*:\s*")[^"]*(")'
    $replaced = [regex]::Replace($manifest, $pattern, "`${1}$($staged[$entry.path])`${2}")
    if ($replaced -eq $manifest -and $entry.sha256 -ne $staged[$entry.path]) {
        throw "Could not rewrite the manifest hash for $($entry.path)"
    }
    $manifest = $replaced
    $updated++
}
Set-Content -LiteralPath $manifestPath -Value $manifest -NoNewline -Encoding utf8

if ($manifest.Contains('BUILD_OUTPUT_PENDING')) {
    throw 'manifest.json still carries a BUILD_OUTPUT_PENDING placeholder'
}
Write-Host "Refreshed $updated manifest hashes and the SHA256SUMS.txt paddleocr block"
