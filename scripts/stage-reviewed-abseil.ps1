# Prepare the reviewed Abseil source for Protobuf on a GitHub-hosted runner.
# Static source extraction only; this script does not compile or execute Abseil.
# Invoke after the Goldberg dependency extraction step and before building Protobuf.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$zipPath = Join-Path $repoRoot 'reviewed-deps/abseil/abseil-cpp-20250512.1.zip'
$expectedHash = '65AEF88DA5BBDC7C59D3A87A3D320A5B7C5560397BD41AE55E46C0EA04E77EDE'

if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
    throw "Missing reviewed Abseil ZIP: $zipPath"
}
$actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash) {
    throw "Abseil ZIP SHA-256 mismatch: $actualHash"
}

# This matches Goldberg's default --deps-dir when the VS2022 action is used.
$depsRoot = Join-Path $repoRoot 'build/deps/win/vs2022'
if (-not (Test-Path -LiteralPath $depsRoot -PathType Container)) {
    throw "Missing extracted dependency directory: $depsRoot. Run dependency preparation first."
}

$destination = Join-Path $depsRoot 'abseil'
$tempDir = Join-Path $depsRoot '_abseil_reviewed_extract'
if ((Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath $tempDir)) {
    throw 'Abseil destination or temporary directory already exists; refusing to overwrite.'
}

New-Item -ItemType Directory -Path $tempDir -ErrorAction Stop | Out-Null
try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $tempDir -ErrorAction Stop
    $extractedRoot = Join-Path $tempDir 'abseil-cpp-20250512.1'
    $cmakeFile = Join-Path $extractedRoot 'CMakeLists.txt'
    if (-not (Test-Path -LiteralPath $cmakeFile -PathType Leaf)) {
        throw 'Unexpected Abseil archive folder structure: missing CMakeLists.txt.'
    }
    $fileCount = @(Get-ChildItem -LiteralPath $extractedRoot -File -Recurse).Count
    if ($fileCount -ne 1532) {
        throw "Unexpected Abseil file count: $fileCount (expected 1532)."
    }
    Move-Item -LiteralPath $extractedRoot -Destination $destination -ErrorAction Stop
} finally {
    if (Test-Path -LiteralPath $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force
    }
}

Write-Host "Abseil 20250512.1 verified and staged at: $destination"
Write-Host 'No source code was compiled or executed.'
