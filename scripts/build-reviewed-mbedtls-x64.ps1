# Build only reviewed Mbed TLS 3.6.7 for Windows x64 on a hosted GitHub Actions runner.
# Requires the successful reviewed-source preparation steps to run first.
# Do NOT execute this script on your personal Windows computer.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Avoid accidental local execution or execution from the wrong workflow branch.
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_REF -cne 'refs/heads/security-hardening') {
    throw 'Mbed TLS build is restricted to GitHub Actions Windows on security-hardening.'
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$premake = Join-Path $root 'third-party/common/win/premake/premake5.exe'
$cmake = Join-Path $root 'third-party/deps/win/cmake/bin/cmake.exe'
$sourceArchive = Join-Path $root 'reviewed-deps/mbedtls/mbedtls-3.6.7-for-goldberg.tar.gz'
$sourceCmake = Join-Path $root 'build/deps/win/vs2022/mbedtls/CMakeLists.txt'
$sourceLibraryCmake = Join-Path $root 'build/deps/win/vs2022/mbedtls/library/CMakeLists.txt'
$installRoot = Join-Path $root 'build/deps/win/vs2022/mbedtls/install64'
$libraryDir = Join-Path $installRoot 'lib'

# Check input identity before running any staged executable.
$required = @(
    @{Path=$premake; SHA256='2301E3E23FF3074CB83A5EA6103D68C7EA81DAD56B786807C84B0643CDDEA31B'},
    @{Path=$cmake; SHA256='DAAE341E73330C9C5BF391F22D10510C0F70E5F01D2B61B0FD256CD9EDD28379'},
    @{Path=$sourceArchive; SHA256='E39AB80643869DB511A64563B09A7B2D0343E0A9BA53515A3946D5DE28B8C6D8'}
)
foreach ($item in $required) {
    if (-not (Test-Path -LiteralPath $item.Path -PathType Leaf)) {
        throw "Missing reviewed input: $($item.Path)"
    }
    $actual = (Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash
    if ($actual -cne $item.SHA256) {
        throw "SHA-256 mismatch at $($item.Path). Expected $($item.SHA256); got $actual"
    }
}

foreach ($source in @($sourceCmake, $sourceLibraryCmake)) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Mbed TLS source was not prepared by preflight: $source"
    }
}

$libraryNames = @('mbedcrypto.lib', 'mbedx509.lib', 'mbedtls.lib')
foreach ($name in $libraryNames) {
    if (Test-Path -LiteralPath (Join-Path $libraryDir $name)) {
        throw "Existing Mbed TLS library detected ($name). Refusing to reuse a prior output."
    }
}

# VS2022 x64 target selection is handled by the reviewed Premake build helper.
$env:CMAKE_GENERATOR = 'Visual Studio 17 2022'

Push-Location -LiteralPath $root
try {
    & $premake '--file=premake5-deps.lua' '--os=windows' `
        '--64-build' '--build-mbedtls' 'vs2022'
    if ($LASTEXITCODE -ne 0) {
        throw "Premake Mbed TLS x64 build failed (exit code $LASTEXITCODE)."
    }
}
finally {
    Pop-Location
}

# Verify and record each of the three installed static libraries.
foreach ($name in $libraryNames) {
    $file = Join-Path $libraryDir $name
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Expected x64 static Mbed TLS library not installed: $file"
    }
    $item = Get-Item -LiteralPath $file
    if ($item.Length -le 0) {
        throw "Mbed TLS library is empty: $file"
    }
    Write-Host "Mbed TLS x64 library: $file"
    Write-Host "File size: $($item.Length) bytes"
    Write-Host "SHA-256: $((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash)"
}

# Tests and shared libraries are disabled in the reviewed CMake configuration.
# Treat unexpected installed binaries as a build outcome requiring investigation.
$unexpected = @(Get-ChildItem -LiteralPath $installRoot -File -Recurse -ErrorAction Stop |
    Where-Object { $_.Extension -in @('.dll', '.exe') })
if ($unexpected.Count -ne 0) {
    throw "Unexpected installed executable/shared library: $($unexpected.FullName -join ', ')"
}

Write-Host 'Reviewed Mbed TLS x64 static-library build step completed. No Goldberg DLL compiled.'
