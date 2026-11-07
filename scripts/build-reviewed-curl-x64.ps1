
# Build only the reviewed Curl source for Windows x64 in GitHub Actions.
# Intended to run AFTER the reviewed source preflight, Zlib and Mbed TLS builds.
# Do not execute this script on a personal computer.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Restrict execution to the designated GitHub Actions environment.
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_REF -cne 'refs/heads/security-hardening') {
    throw 'This build is restricted to GitHub Actions Windows on security-hardening.'
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

$premake = Join-Path $root 'third-party/common/win/premake/premake5.exe'
$cmake = Join-Path $root 'third-party/deps/win/cmake/bin/cmake.exe'

$depsRoot = Join-Path $root 'build/deps/win/vs2022'

$curlSource = Join-Path $depsRoot 'curl/CMakeLists.txt'
$curlInstall = Join-Path $depsRoot 'curl/install64'

# Verify the reviewed build tools before invoking them.
$tools = @(
    @{
        Path = $premake
        SHA256 = '2301E3E23FF3074CB83A5EA6103D68C7EA81DAD56B786807C84B0643CDDEA31B'
    },
    @{
        Path = $cmake
        SHA256 = 'DAAE341E73330C9C5BF391F22D10510C0F70E5F01D2B61B0FD256CD9EDD28379'
    }
)

foreach ($tool in $tools) {
    if (-not (Test-Path -LiteralPath $tool.Path -PathType Leaf)) {
        throw "Missing reviewed build tool: $($tool.Path)"
    }

    $actual = (Get-FileHash -LiteralPath $tool.Path -Algorithm SHA256).Hash

    if ($actual -ne $tool.SHA256) {
        throw "Build tool SHA-256 mismatch: $($tool.Path)"
    }
}

# Confirm reviewed source and dependency outputs exist.
$requiredFiles = @(
    $curlSource,
    (Join-Path $depsRoot 'zlib/install64/lib/zs.lib'),
    (Join-Path $depsRoot 'zlib/install64/include/zlib.h'),
    (Join-Path $depsRoot 'mbedtls/install64/lib/mbedtls.lib'),
    (Join-Path $depsRoot 'mbedtls/install64/lib/mbedcrypto.lib'),
    (Join-Path $depsRoot 'mbedtls/install64/lib/mbedx509.lib'),
    (Join-Path $depsRoot 'mbedtls/install64/include/mbedtls/ssl.h')
)

foreach ($file in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Required source or dependency missing: $file"
    }

    if ((Get-Item -LiteralPath $file).Length -le 0) {
        throw "Required file is empty: $file"
    }
}

# Refuse to reuse an existing Curl installation.
if (Test-Path -LiteralPath $curlInstall) {
    throw 'Curl installation directory already exists. Refusing to reuse earlier output.'
}

# Match the reviewed Windows x64 build configuration.
$env:CMAKE_GENERATOR = 'Visual Studio 17 2022'

Push-Location -LiteralPath $root
try {
    & $premake '--file=premake5-deps.lua' '--os=windows' `
        '--64-build' '--build-curl' 'vs2022'

    if ($LASTEXITCODE -ne 0) {
        throw "Curl x64 build failed (exit code $LASTEXITCODE)."
    }
}
finally {
    Pop-Location
}

# Identify the installed Curl static-library candidate.
$libraryDir = Join-Path $curlInstall 'lib'

if (-not (Test-Path -LiteralPath $libraryDir -PathType Container)) {
    throw 'Curl installation library directory was not created.'
}

$libraries = @(Get-ChildItem -LiteralPath $libraryDir -File |
    Where-Object { $_.Name -match '(?i)curl.*\.lib$' })

if ($libraries.Count -ne 1) {
    throw "Expected exactly one Curl library; found $($libraries.Count)."
}

$built = $libraries[0]

if ($built.Length -le 0) {
    throw "Curl library is empty: $($built.FullName)"
}

Write-Host "Curl x64 library: $($built.FullName)"
Write-Host "File size: $($built.Length) bytes"
Write-Host "SHA-256: $((Get-FileHash -LiteralPath $built.FullName -Algorithm SHA256).Hash)"

# Reject unexpected installed executables and shared libraries.
$unexpected = @(Get-ChildItem -LiteralPath $curlInstall -File -Recurse |
    Where-Object { $_.Extension -in @('.exe', '.dll') })

if ($unexpected.Count -ne 0) {
    throw "Unexpected Curl executable/shared library: $($unexpected.FullName -join ', ')"
}

Write-Host 'Reviewed Curl x64 library build step completed. No Goldberg DLL compiled.'
