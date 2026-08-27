$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '..\tools\RuntimeInputLock.ps1')

function Assert-LockRejectsMutation {
    param([string]$Description, [scriptblock]$Mutate)

    $manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\runtime-inputs.bootstrap-fixture.json') -Raw | ConvertFrom-Json
    & $Mutate $manifest
    $temporary = Join-Path ([IO.Path]::GetTempPath()) "runtime-input-$([Guid]::NewGuid()).json"
    try {
        [IO.File]::WriteAllText($temporary, ($manifest | ConvertTo-Json -Depth 10))
        try {
            Read-RuntimeInputLock -Path $temporary | Out-Null
            throw "$Description was accepted."
        }
        catch {
            if ($_.Exception.Message -eq "$Description was accepted.") { throw }
        }
    }
    finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}

Assert-LockRejectsMutation -Description 'A case-variant required root property' -Mutate {
    param($manifest)
    $value = $manifest.PSObject.Properties['schemaVersion'].Value
    $manifest.PSObject.Properties.Remove('schemaVersion')
    $manifest | Add-Member -NotePropertyName 'SchemaVersion' -NotePropertyValue $value
}
Assert-LockRejectsMutation -Description 'A case-variant required input property' -Mutate {
    param($manifest)
    $value = $manifest.inputs[0].PSObject.Properties['fileName'].Value
    $manifest.inputs[0].PSObject.Properties.Remove('fileName')
    $manifest.inputs[0] | Add-Member -NotePropertyName 'FileName' -NotePropertyValue $value
}
Assert-LockRejectsMutation -Description 'A case-variant feature enum value' -Mutate {
    param($manifest)
    $manifest.inputs[0].feature = 'VC-REDIST-V14'
}
Assert-LockRejectsMutation -Description 'A case-variant architecture enum value' -Mutate {
    param($manifest)
    $manifest.inputs[0].architecture = 'X64'
}
Assert-LockRejectsMutation -Description 'A credential-bearing source URL' -Mutate {
    param($manifest)
    $manifest.inputs[0].sourceUrl = 'https://user:pass@download.microsoft.com/fixture.exe'
}
Assert-LockRejectsMutation -Description 'A credential-bearing license URL' -Mutate {
    param($manifest)
    $manifest.inputs[0].licenseUrl = 'https://user:pass@www.microsoft.com/licensing/'
}

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
$quotedCommaSubject = 'CN="Contoso, O=Microsoft Corporation, subsidiary", O=Contoso Ltd'
$quotedCommaValidSignature = [pscustomobject]@{
    Status = 'Valid'
    SignerCertificate = [pscustomobject]@{ Subject = $quotedCommaSubject }
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
if (Test-ApprovedAuthenticodeSignature -Signature $quotedCommaValidSignature -ExpectedSubject $approved) {
    throw 'A quoted common name was split into a false Microsoft organization.'
}
if (-not (Test-ApprovedSignerSubject -Expected $approved -Actual 'CN="Runtime, Pack", O=Microsoft Corporation')) {
    throw 'A valid Microsoft organization with a quoted common name was not recognized.'
}
if (Test-ApprovedSignerSubject -Expected 'microsoft corporation' -Actual 'CN=Microsoft Corporation, O=Microsoft Corporation') {
    throw 'A lockfile signer policy with different casing was accepted.'
}

Write-Host 'Runtime input lock validation tests passed.'
