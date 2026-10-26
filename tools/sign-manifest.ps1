# Signs the catalogue manifest with the keeper's minisign key.
#
# The daemon fetches catalog/index.json.minisig next to index.json and verifies it
# against the keyring baked into its executable before anything is parsed, so a
# manifest change is not published until it is also signed:
#
#   pwsh tools/sign-manifest.ps1
#
# The key lives OUTSIDE the repository (the keeper's ~/.minisign folder by default);
# nothing in this repository signs anything. The signing tool itself comes from
# winget: `winget install jedisct1.minisign`.
#
# -Key    optional: another minisign secret key file; the default is
#         `~\.minisign\ArmouryDaemonCatalog.key`.
param(
    [string]$Key = "$env:USERPROFILE\.minisign\ArmouryDaemonCatalog.key"
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command minisign -ErrorAction SilentlyContinue)) {
    throw 'minisign is not on PATH - install it with `winget install jedisct1.minisign`'
}
if (-not (Test-Path -LiteralPath $Key -PathType Leaf)) {
    throw "the signing key is not at $Key - put ArmouryDaemonCatalog.key there, or pass -Key"
}

$manifest = Join-Path $PSScriptRoot '..\catalog\index.json'
$manifest = (Resolve-Path -LiteralPath $manifest).Path

minisign -S -W -m $manifest -s $Key -c 'ArmouryDaemon catalogue'
if ($LASTEXITCODE -ne 0) { throw "minisign failed with exit code $LASTEXITCODE" }

$sigPath = "$manifest.minisig"
if (-not (Test-Path -LiteralPath $sigPath -PathType Leaf)) {
    throw "minisign did not leave a signature where it should have: $sigPath"
}

# The check the daemon will do itself: a signature made for other bytes than the ones
# on disk would never verify, and now is the moment to find out, not at the CDN.
$pubKey = $Key -replace '\.key$', '.pub'
if (Test-Path -LiteralPath $pubKey -PathType Leaf) {
    minisign -Vm $manifest -P ((Get-Content $pubKey | Select-Object -Skip 1).Trim())
    if ($LASTEXITCODE -ne 0) { throw 'the fresh signature does not verify against its own public key' }
}

Write-Host "signed: $sigPath ($((Get-Item -LiteralPath $sigPath).Length) bytes)"
