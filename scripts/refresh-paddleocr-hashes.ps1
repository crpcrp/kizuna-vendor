<#
.SYNOPSIS
    Rewrites the recorded SHA-256 hashes for the staged paddleocr/ payload.

.DESCRIPTION
    Recomputes every paddleocr/ line in SHA256SUMS.txt and every "sha256" value
    the win32 components record for a paddleocr/ path in manifest.json, so both
    files match whatever build-paddleocr-win-x64.ps1 just staged.

    Both the runtime component and the model component are refreshed, and every
    staged file must be recorded by one of them. Kizuna cross-checks the
    manifest against its own resources.lock.json, so a path this script leaves
    behind is a payload Kizuna will reject rather than one it silently accepts.

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
# LF, not Set-Content's CRLF: publish-payloads.sh packages the working tree, so
# a file whose line endings differ from the committed ones would make the same
# commit produce two different archive hashes depending on who packaged it.
[System.IO.File]::WriteAllText(
    $sumsPath,
    ((@($before) + @($paddleLines) + @($after)) -join "`n") + "`n",
    [System.Text.ASCIIEncoding]::new())

# manifest.json: update the sha256 that follows each recorded paddleocr path.
# The models live in their own component, so selecting components by name would
# quietly leave half the payload on a stale hash.
$manifest = Get-Content -LiteralPath $manifestPath -Raw
$components = @((Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).payloads |
    Where-Object { $_.platform -eq 'win32' } |
    ForEach-Object { $_.components } |
    Where-Object { @($_.files.path) -like 'paddleocr/*' })
if (-not $components) { throw 'manifest.json has no win32 component recording paddleocr files' }

$updated = 0
$recorded = [System.Collections.Generic.HashSet[string]]::new()
foreach ($component in $components) {
    foreach ($entry in $component.files) {
        if ($entry.path -notlike 'paddleocr/*') { continue }
        if (-not $staged.Contains($entry.path)) {
            throw "manifest.json records $($entry.path), which the build did not stage"
        }
        $pattern = '(?s)("path"\s*:\s*"' + [regex]::Escape($entry.path) + '"\s*,\s*"sha256"\s*:\s*")[^"]*(")'
        $replaced = [regex]::Replace($manifest, $pattern, "`${1}$($staged[$entry.path])`${2}")
        if ($replaced -eq $manifest -and $entry.sha256 -ne $staged[$entry.path]) {
            throw "Could not rewrite the manifest hash for $($entry.path)"
        }
        $manifest = $replaced
        [void]$recorded.Add($entry.path)
        $updated++
    }
}

# Anything staged but unrecorded travels in the payload without a manifest
# entry Kizuna can cross-check. License texts are recorded by path only, so
# they count as covered when they appear in a licenseFiles list.
foreach ($component in @((Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).payloads |
        Where-Object { $_.platform -eq 'win32' } | ForEach-Object { $_.components })) {
    foreach ($licensePath in $component.licenseFiles) { [void]$recorded.Add($licensePath) }
}
# The worker source is corresponding source for the GPL binary, not a runtime
# file Kizuna stages; scripts/ and the notices record it instead.
$unrecorded = @($staged.Keys | Where-Object {
        -not $recorded.Contains($_) -and $_ -notlike 'paddleocr/worker/*'
    })
if ($unrecorded) {
    throw "manifest.json records no entry for: $($unrecorded -join ', ')"
}

# Not Set-Content -Encoding utf8: Windows PowerShell 5.1 writes a BOM, and
# Kizuna reads this file with JSON.parse, which rejects one outright.
[System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))

if ($manifest.Contains('BUILD_OUTPUT_PENDING')) {
    throw 'manifest.json still carries a BUILD_OUTPUT_PENDING placeholder'
}
Write-Host "Refreshed $updated manifest hashes and the SHA256SUMS.txt paddleocr block"
