# Build only the reviewed Zlib source for Windows x64 in GitHub Actions.
# Intended to run AFTER the successful reviewed-source preflight steps.
# Do not execute this script on a personal computer.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Refuse to run outside the designated, manually selected GitHub Actions branch.
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_REF -cne 'refs/heads/security-hardening') {
    throw 'This build is restricted to GitHub Actions Windows on security-hardening.'
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$premake = Join-Path $root 'third-party/common/win/premake/premake5.exe'
$cmake = Join-Path $root 'third-party/deps/win/cmake/bin/cmake.exe'
$zlibSource = Join-Path $root 'build/deps/win/vs2022/zlib/CMakeLists.txt'
$zlibLibrary = Join-Path $root 'build/deps/win/vs2022/zlib/install64/lib/zs.lib'

$required = @(
    @{Path=$premake; SHA256='2301E3E23FF3074CB83A5EA6103D68C7EA81DAD56B786807C84B0643CDDEA31B'},
    @{Path=$cmake; SHA256='DAAE341E73330C9C5BF391F22D10510C0F70E5F01D2B61B0FD256CD9EDD28379'}
)
foreach ($item in $required) {
    if (-not (Test-Path -LiteralPath $item.Path -PathType Leaf)) {
        throw "Missing verified build tool: $($item.Path)"
    }
    $actual = (Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash
    if ($actual -ne $item.SHA256) {
        throw "Build tool SHA-256 mismatch at $($item.Path). Expected $($item.SHA256); got $actual"
    }
}
if (-not (Test-Path -LiteralPath $zlibSource -PathType Leaf)) {
    throw "Zlib source not prepared; preflight must run first: $zlibSource"
}
if (Test-Path -LiteralPath $zlibLibrary) {
    throw 'Zlib output already exists. Refusing to reuse an earlier build.'
}

# Select VS2022 explicitly, rather than depending on a runner's defaults.
$env:CMAKE_GENERATOR = 'Visual Studio 17 2022'

Push-Location -LiteralPath $root
try {
    & $premake '--file=premake5-deps.lua' '--os=windows' `
        '--64-build' '--build-zlib' 'vs2022'
    if ($LASTEXITCODE -ne 0) {
        throw "Premake Zlib x64 build failed (exit code $LASTEXITCODE)."
    }
}
finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $zlibLibrary -PathType Leaf)) {
    throw "Expected 64-bit static library not installed: $zlibLibrary"
}
$built = Get-Item -LiteralPath $zlibLibrary
if ($built.Length -le 0) {
    throw 'Zlib static library is empty.'
}
Write-Host "Zlib x64 library: $zlibLibrary"
Write-Host "File size: $($built.Length) bytes"
Write-Host "SHA-256: $((Get-FileHash -LiteralPath $zlibLibrary -Algorithm SHA256).Hash)"
Write-Host 'Reviewed Zlib x64 build step completed. No Goldberg DLL compiled.'
