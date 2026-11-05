# Stage SHA-256-verified Windows build tools and Goldberg dependency archives.
# For a disposable GitHub-hosted Windows Actions runner ONLY.
# Does not invoke any extracted executable, compiler, or third-party script.
# The existing dependency preparation step runs separately, after this one.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'This staging script is intended only for a GitHub Actions Windows runner.'
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$reviewed = Join-Path $repoRoot 'reviewed-build-tools'
$thirdPartyRoot = Join-Path $repoRoot 'third-party'
$archiveWin = Join-Path $reviewed 'deps-win/gbe_fork-third-party-deps-win.zip'
$archiveCommon = Join-Path $reviewed 'deps-common/gbe_fork-third-party-deps-common.zip'
$localPremake = Join-Path $reviewed 'common-win/premake/premake5.exe'
$localVswhere = Join-Path $reviewed 'common-win/vswhere/vswhere.exe'

function Assert-SHA256([string]$filePath, [string]$expected) {
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        throw "Missing required file: $filePath"
    }
    $actual = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
    if ($actual -ne $expected) {
        throw "SHA-256 mismatch: $filePath`nExpected: $expected`nActual:   $actual"
    }
}

# Verify every original source package and locally selected executable before copying.
Assert-SHA256 $archiveWin 'A9287EC4C5456E71A114ADE9201AE858EA2F317278DF05BEF58B8F9B20EE5F9C'
Assert-SHA256 $archiveCommon 'D82FB0FF75E1CAEFD1660588EAD7E856EABB1B5506EF38AD391FC7745CBDEC1C'
Assert-SHA256 $localPremake '2301E3E23FF3074CB83A5EA6103D68C7EA81DAD56B786807C84B0643CDDEA31B'
Assert-SHA256 $localVswhere 'C54F3B7C9164EA9A0DB8641E81ECDDA80C2664EF5A47C4191406F848CC07C662'

# Refuse to modify existing third-party material: the workflow must use a fresh checkout.
if (Test-Path -LiteralPath $thirdPartyRoot) {
    throw 'third-party already exists; refusing to overwrite it.'
}
if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    throw 'RUNNER_TEMP is not available.'
}
$stageRoot = Join-Path $env:RUNNER_TEMP 'gbe-reviewed-tool-archives'
if (Test-Path -LiteralPath $stageRoot) {
    throw 'Temporary staging directory already exists; refusing to overwrite it.'
}

New-Item -ItemType Directory -Path $stageRoot | Out-Null
try {
    $stagedWin = Join-Path $stageRoot 'win'
    $stagedCommon = Join-Path $stageRoot 'common'
    Expand-Archive -LiteralPath $archiveWin -DestinationPath $stagedWin -ErrorAction Stop
    Expand-Archive -LiteralPath $archiveCommon -DestinationPath $stagedCommon -ErrorAction Stop

    $sourceWin = Join-Path $stagedWin 'gbe_fork-third-party-deps-win'
    $sourceCommon = Join-Path $stagedCommon 'gbe_fork-third-party-deps-common'
    foreach ($required in @(
        (Join-Path $sourceWin '7za/7za.exe'),
        (Join-Path $sourceWin 'cmake/bin/cmake.exe'),
        (Join-Path $sourceCommon 'protobuf/protobuf.tar.gz'),
        (Join-Path $sourceCommon 'libssq/libssq.tar.gz'),
        (Join-Path $sourceCommon 'sdl/sdl.tar.gz')
    )) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Unexpected archive layout; missing: $required"
        }
    }

    # Verify executable content inside the already hash-checked Windows ZIP.
    Assert-SHA256 (Join-Path $sourceWin '7za/7za.exe') '2C39B62EDF81F576DCB1A80679B0EBFC67787761236E38C78466AF026C8A60FA'
    Assert-SHA256 (Join-Path $sourceWin 'cmake/bin/cmake.exe') 'DAAE341E73330C9C5BF391F22D10510C0F70E5F01D2B61B0FD256CD9EDD28379'

    $targetCommonWin = Join-Path $thirdPartyRoot 'common/win'
    $targetDepsWin = Join-Path $thirdPartyRoot 'deps/win'
    $targetDepsCommon = Join-Path $thirdPartyRoot 'deps/common'
    foreach ($destination in @($targetCommonWin, $targetDepsWin, $targetDepsCommon)) {
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
    }

    # Stage only the explicitly reviewed Premake and vswhere folders (no LuaSocket DLL).
    foreach ($folder in @('premake', 'vswhere')) {
        $source = Join-Path (Join-Path $reviewed 'common-win') $folder
        if (-not (Test-Path -LiteralPath $source -PathType Container)) {
            throw "Missing reviewed build-tool directory: $source"
        }
        Copy-Item -LiteralPath $source -Destination $targetCommonWin -Recurse -ErrorAction Stop
    }
    if (Test-Path -LiteralPath (Join-Path $targetCommonWin 'premake/luasocket.dll')) {
        throw 'Unexpected LuaSocket DLL; refusing to proceed.'
    }

    # Stage the original Windows tool tree (including CMake share files).
    foreach ($entry in (Get-ChildItem -LiteralPath $sourceWin -Force)) {
        Copy-Item -LiteralPath $entry.FullName -Destination $targetDepsWin -Recurse -ErrorAction Stop
    }

    # Stage only the eight required source libraries. The optional overlay is excluded.
    foreach ($folder in @('zlib', 'libssq', 'curl', 'mbedtls', 'protobuf', 'sdl', 'opus', 'portaudio')) {
        $source = Join-Path $sourceCommon $folder
        if (-not (Test-Path -LiteralPath $source -PathType Container)) {
            throw "Missing dependency directory in source ZIP: $source"
        }
        Copy-Item -LiteralPath $source -Destination $targetDepsCommon -Recurse -ErrorAction Stop
    }

    # Recheck paths that the existing preparation script will consume.
    Assert-SHA256 (Join-Path $targetCommonWin 'premake/premake5.exe') '2301E3E23FF3074CB83A5EA6103D68C7EA81DAD56B786807C84B0643CDDEA31B'
    Assert-SHA256 (Join-Path $targetCommonWin 'vswhere/vswhere.exe') 'C54F3B7C9164EA9A0DB8641E81ECDDA80C2664EF5A47C4191406F848CC07C662'
    Assert-SHA256 (Join-Path $targetDepsWin '7za/7za.exe') '2C39B62EDF81F576DCB1A80679B0EBFC67787761236E38C78466AF026C8A60FA'
    Assert-SHA256 (Join-Path $targetDepsWin 'cmake/bin/cmake.exe') 'DAAE341E73330C9C5BF391F22D10510C0F70E5F01D2B61B0FD256CD9EDD28379'

    Write-Host 'Reviewed Windows build tools and eight dependency archives staged successfully.'
    Write-Host 'Optional LuaSocket and in-game overlay are not staged.'
    Write-Host 'Nothing was compiled or executed from the staged tools.'
}
finally {
    if (Test-Path -LiteralPath $stageRoot) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }
}
