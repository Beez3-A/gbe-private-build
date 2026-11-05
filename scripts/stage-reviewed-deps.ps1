# Stage the two reviewed dependency source archives for Goldberg's existing
# dependency extractor. Intended for a controlled GitHub Actions Windows build.
# This script only verifies SHA-256 hashes and copies archives; it does not
# extract archives, execute their contents, or run a compiler.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

$archives = @(
    @{
        Source = 'reviewed-deps/mbedtls/mbedtls-3.6.7-for-goldberg.tar.gz'
        Target = 'third-party/deps/common/mbedtls/mbedtls.tar.gz'
        SHA256 = 'E39AB80643869DB511A64563B09A7B2D0343E0A9BA53515A3946D5DE28B8C6D8'
    },
    @{
        Source = 'reviewed-deps/curl/curl-8.23.0-for-goldberg.tar.gz'
        Target = 'third-party/deps/common/curl/curl.tar.gz'
        SHA256 = '1C5FC48F6C5D95101D67D28158B8DB8C8D420B1807FB5949DECDB8A4598F51A6'
    }
)

foreach ($archive in $archives) {
    $sourcePath = Join-Path $repoRoot $archive.Source
    $targetPath = Join-Path $repoRoot $archive.Target

    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Missing reviewed archive: $sourcePath"
    }
    if (-not (Test-Path -LiteralPath (Split-Path -Path $targetPath -Parent) -PathType Container)) {
        throw "Missing third-party dependency directory: $targetPath. Checkout the dependency source branch first."
    }

    $actual = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
    if ($actual -ne $archive.SHA256) {
        throw "Checksum mismatch for $sourcePath. Expected $($archive.SHA256), got $actual."
    }

    Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force

    $staged = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash
    if ($staged -ne $archive.SHA256) {
        throw "Checksum mismatch after staging: $targetPath"
    }
    Write-Host "Verified and staged: $($archive.Target)"
}
