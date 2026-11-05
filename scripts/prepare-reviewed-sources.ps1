# Prepare the reviewed dependency sources in a GitHub-hosted Windows build.
# Run ONLY on the GitHub Actions runner after the pinned third-party branches
# have been checked out into third-party/common/win, third-party/deps/win,
# and third-party/deps/common. This is NOT a script to run on your main PC.
# It stages the updated archives, extracts only the libraries needed by
# api_regular, and then applies the reviewed libssq query.c patch.
# It does not compile any library or produce a DLL.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$premake  = Join-Path $repoRoot 'third-party/common/win/premake/premake5.exe'
$extractor = Join-Path $repoRoot 'third-party/deps/win/7za/7za.exe'

# Stop if the extracted build tools are not the copies previously compared
# against their official binary distributions.
$toolsToVerify = @(
    @{ Path = $premake;   SHA256 = '2301E3E23FF3074CB83A5EA6103D68C7EA81DAD56B786807C84B0643CDDEA31B' },
    @{ Path = $extractor; SHA256 = '2C39B62EDF81F576DCB1A80679B0EBFC67787761236E38C78466AF026C8A60FA' }
)
foreach ($item in $toolsToVerify) {
    if (-not (Test-Path -LiteralPath $item.Path -PathType Leaf)) {
        throw "Missing required tool: $($item.Path)"
    }
    $actualHash = (Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash
    if ($actualHash -ne $item.SHA256) {
        throw "Build-tool hash mismatch at $($item.Path): $actualHash"
    }
}

# Stage the exact curl and Mbed TLS source archives previously reviewed.
& (Join-Path $PSScriptRoot 'stage-reviewed-deps.ps1')

Push-Location -LiteralPath $repoRoot
try {
    # Extraction ONLY. Do not pass --all-build here: the libssq patch must
    # be applied after extraction but BEFORE any CMake compilation.
    & $premake '--file=premake5-deps.lua' '--os=windows' `
        '--ext-ssq' '--ext-zlib' '--ext-curl' '--ext-protobuf' `
        '--ext-mbedtls' '--ext-sdl' '--ext-opus' '--ext-portaudio' `
        'vs2022'

    if ($LASTEXITCODE -ne 0) {
        throw "Premake dependency extraction failed (exit $LASTEXITCODE)."
    }
} finally {
    Pop-Location
}

# The patch script checks both the original and replacement SHA-256 values.
& (Join-Path $PSScriptRoot 'apply-reviewed-libssq-patch.ps1')
Write-Host 'Reviewed dependency sources extracted and libssq patch verified.'
Write-Host 'No libraries have been compiled.'
