# Apply the previously reviewed libssq query.c change after dependency extraction.
# Intended to run ONLY on the controlled GitHub Actions Windows runner,
# after extracting libssq and before compiling it.
# Does not download, build, or execute any code from the dependency.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$replacement = Join-Path $repoRoot 'security-patches/libssq/query.c'
$destination = Join-Path $repoRoot 'build/deps/win/vs2022/libssq/src/query.c'

# Hashes are for the exact files already statically inspected.
$expectedOriginal = '230407C866F2F59720783AEA9F8DFDCE9228BAE5B703A19DD7F84464B225A5D8'
$expectedReplacement = '97B0AA8A054971FED0015D2DCF2C9F005885728E32D9C559443B2FCAC87FD404'

foreach ($file in @($replacement, $destination)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Required file not found: $file"
    }
}

$replacementHash = (Get-FileHash -LiteralPath $replacement -Algorithm SHA256).Hash
if ($replacementHash -ne $expectedReplacement) {
    throw "Unexpected libssq replacement file. Expected $expectedReplacement; got $replacementHash"
}

$originalHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
if ($originalHash -eq $expectedReplacement) {
    Write-Host 'libssq already patched and verified.'
    return
}
if ($originalHash -ne $expectedOriginal) {
    throw "Unexpected extracted libssq query.c. Refusing to overwrite. Hash: $originalHash"
}

Copy-Item -LiteralPath $replacement -Destination $destination -Force
$afterHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
if ($afterHash -ne $expectedReplacement) {
    throw "libssq patch verification failed; resulting hash $afterHash"
}
Write-Host 'libssq query.c successfully replaced and SHA-256 verified.'
