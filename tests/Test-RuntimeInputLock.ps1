$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '..\tools\RuntimeInputLock.ps1')

$approved = 'Microsoft Corporation'
$unrelatedSubject = 'CN=Contoso Software, O=Contoso Ltd'
$unrelatedValidSignature = [pscustomobject]@{
    Status = 'Valid'
    SignerCertificate = [pscustomobject]@{ Subject = $unrelatedSubject }
}
$misleadingSubject = 'CN=Microsoft Corporation Tools, O=Contoso Ltd'
$misleadingValidSignature = [pscustomobject]@{
    Status = 'Valid'
    SignerCertificate = [pscustomobject]@{ Subject = $misleadingSubject }
}
foreach ($metacharacter in '*', '?', '[Microsoft Corporation]') {
    if (Test-ApprovedAuthenticodeSignature -Signature $unrelatedValidSignature -ExpectedSubject $metacharacter) {
        throw "Wildcard signer policy '$metacharacter' accepted an unrelated valid Authenticode signature."
    }

    $manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\runtime-inputs.bootstrap-fixture.json') -Raw | ConvertFrom-Json
    $manifest.inputs[0].signerSubjectContains = $metacharacter
    $temporary = Join-Path ([IO.Path]::GetTempPath()) "runtime-input-$([Guid]::NewGuid()).json"
    try {
        [IO.File]::WriteAllText($temporary, ($manifest | ConvertTo-Json -Depth 10))
        try {
            Read-RuntimeInputLock -Path $temporary | Out-Null
            throw "Signer policy '$metacharacter' was accepted."
        }
        catch {
            if ($_.Exception.Message -notmatch 'unapproved signerSubjectContains') { throw }
        }
    }
    finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}

if (-not (Test-ApprovedSignerSubject -Expected $approved -Actual 'CN=Microsoft Corporation, O=Microsoft Corporation')) {
    throw 'The approved literal signer was not recognized.'
}
if (Test-ApprovedAuthenticodeSignature -Signature $misleadingValidSignature -ExpectedSubject $approved) {
    throw 'A non-Microsoft organization with Microsoft Corporation in its common name was accepted.'
}
if (Test-ApprovedSignerSubject -Expected 'microsoft corporation' -Actual 'CN=Microsoft Corporation, O=Microsoft Corporation') {
    throw 'A lockfile signer policy with different casing was accepted.'
}

Write-Host 'Runtime input lock validation tests passed.'
