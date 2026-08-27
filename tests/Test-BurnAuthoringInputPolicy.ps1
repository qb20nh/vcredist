[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$authoringScript = Join-Path $PSScriptRoot '..\tools\New-BurnAuthoring.ps1'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "vcredist-authoring-policy-$([Guid]::NewGuid())"

function Write-MinimalLockFile {
    param([string]$Path, [string]$SourceUrl)

    @{
        schemaVersion = 1
        inputs = @(@{
            id = 'policy-test-x64'; feature = 'vc-redist-v14'; architecture = 'x64'
            fileName = 'policy-test.exe'; sourceUrl = $SourceUrl
            sha256 = 'a' * 64; sha512 = 'b' * 128; size = 1; version = '1.0.0.0'
            signerSubjectContains = 'Microsoft Corporation'; installArguments = '/quiet'
            detectCondition = '0'; licenseUrl = 'https://www.microsoft.com/licensing/'
        })
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Assert-AuthoringRejected {
    param([string]$Name, [string]$SourceUrl)

    $lockFile = Join-Path $temporaryRoot "$Name.json"
    $outputFile = Join-Path $temporaryRoot "$Name.wxs"
    Write-MinimalLockFile -Path $lockFile -SourceUrl $SourceUrl
    try {
        & $authoringScript -Mode Bootstrap -Architecture x64 -LockFile $lockFile -OutputFile $outputFile
        throw "Bootstrap authoring unexpectedly accepted '$SourceUrl'."
    }
    catch {
        if ($_.Exception.Message -like 'Bootstrap authoring unexpectedly*') { throw }
    }
    if (Test-Path -LiteralPath $outputFile) {
        throw "Rejected input '$SourceUrl' created WiX output."
    }
}

New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
try {
    Assert-AuthoringRejected -Name unapproved -SourceUrl 'https://example.invalid/payload.exe'
    Assert-AuthoringRejected -Name nonhttps -SourceUrl 'http://download.microsoft.com/payload.exe'

    $acceptedLock = Join-Path $temporaryRoot 'accepted.json'
    $acceptedOutput = Join-Path $temporaryRoot 'accepted.wxs'
    Write-MinimalLockFile -Path $acceptedLock -SourceUrl 'https://download.microsoft.com/payload.exe'
    & $authoringScript -Mode Bootstrap -Architecture x64 -LockFile $acceptedLock -OutputFile $acceptedOutput
    [xml]$xml = Get-Content -LiteralPath $acceptedOutput -Raw
    $namespace = [Xml.XmlNamespaceManager]::new($xml.NameTable)
    $namespace.AddNamespace('w', 'http://wixtoolset.org/schemas/v4/wxs')
    $payload = $xml.SelectSingleNode('//w:ExePackagePayload', $namespace)
    if ($null -eq $payload -or $payload.DownloadUrl -ne 'https://download.microsoft.com/payload.exe') {
        throw 'Approved HTTPS host did not produce the expected canonical Burn payload.'
    }
}
finally {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'Burn authoring input policy tests passed.'
