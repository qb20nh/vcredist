[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$LockFile,

    [Parameter(Mandatory)]
    [string]$Destination,

    [switch]$NoDownload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'RuntimeInputPolicy.psm1') -Force
. (Join-Path $PSScriptRoot 'RuntimeInputLock.ps1')

function Assert-VerifiedFile {
    param(
        [object]$Input,
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing payload '$Path'."
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.Length -ne [int64]$Input.size) {
        throw "Size mismatch for '$($Input.id)': expected $($Input.size), got $($item.Length)."
    }

    $sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($sha256 -ne $Input.sha256.ToLowerInvariant()) {
        throw "SHA-256 mismatch for '$($Input.id)'."
    }

    $sha512 = (Get-FileHash -LiteralPath $Path -Algorithm SHA512).Hash.ToLowerInvariant()
    if ($sha512 -ne $Input.sha512.ToLowerInvariant()) {
        throw "SHA-512 mismatch for '$($Input.id)'."
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if (-not (Test-ApprovedAuthenticodeSignature -Signature $signature -ExpectedSubject $Input.signerSubjectContains)) {
        throw "Authenticode validation failed for '$($Input.id)': status '$($signature.Status)', subject '$($signature.SignerCertificate.Subject)'."
    }
}

$lock = Read-RuntimeInputLock -Path $LockFile
$resolvedDestination = [IO.Path]::GetFullPath($Destination)
New-Item -ItemType Directory -Force -Path $resolvedDestination | Out-Null

foreach ($input in $lock.inputs | Sort-Object id) {
    $uri = Assert-ApprovedRuntimeInputUrl -SourceUrl $input.sourceUrl -InputId $input.id
    $target = Join-Path $resolvedDestination $input.fileName
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        if ($NoDownload) {
            throw "'$($input.id)' is absent and -NoDownload was specified."
        }

        $temporary = "$target.partial"
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        try {
            Invoke-WebRequest -Uri $uri -OutFile $temporary -MaximumRedirection 0
            Assert-VerifiedFile -Input $input -Path $temporary
            Move-Item -LiteralPath $temporary -Destination $target -Force
        }
        finally {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }

    Assert-VerifiedFile -Input $input -Path $target
    Write-Host "Verified $($input.id)"
}
