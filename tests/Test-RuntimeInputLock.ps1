$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '..\tools\RuntimeInputLock.ps1')

$approved = 'Microsoft Corporation'
$unrelatedSubject = 'CN=Contoso Software, O=Contoso Ltd'
$unrelatedValidSignature = [pscustomobject]@{
    Status = 'Valid'
    SignerCertificate = [pscustomobject]@{ Subject = $unrelatedSubject }
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

Write-Host 'Runtime input lock validation tests passed.'
