[CmdletBinding()]
param(
    [string]$InventoryPath = (Join-Path $PSScriptRoot '..\manifests\runtime-inputs.candidates.json'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\artifacts\runtime-input-evidence'),
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'RuntimeInputPolicy.psm1') -Force
. (Join-Path $PSScriptRoot 'RuntimeInputLock.ps1')

$inventory = Get-Content -LiteralPath $InventoryPath -Raw | ConvertFrom-Json
foreach ($property in 'schemaVersion', 'kind', 'asOf', 'inputs') {
    Assert-LockProperty $inventory $property 'Candidate inventory'
}
if (-not (Test-JsonInteger $inventory.schemaVersion) -or $inventory.schemaVersion -ne 1 -or $inventory.kind -isnot [string] -or
    $inventory.kind -cne 'runtime-input-candidates') {
    throw 'Expected a version 1 runtime-input-candidates inventory, not a release lockfile.'
}
if ($inventory.asOf -isnot [string] -or $inventory.asOf -cnotmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') {
    throw 'Candidate inventory requires an asOf date in YYYY-MM-DD format.'
}
if ($inventory.inputs -isnot [array] -or $inventory.inputs.Count -eq 0) {
    throw 'Candidate inventory must contain a nonempty inputs array.'
}

$ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$fileNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$downloadable = @()
$pending = @()

# Validate the entire inventory before creating output or requesting any payload.
foreach ($candidate in $inventory.inputs) {
    foreach ($property in 'id', 'feature', 'architectures', 'version', 'fileName', 'sourceUrl', 'upstreamSha512') {
        Assert-LockProperty $candidate $property 'Candidate input'
    }
    if ($candidate.id -isnot [string] -or $candidate.id -cnotmatch '^[a-z0-9][a-z0-9-]*$' -or
        -not $ids.Add($candidate.id)) {
        throw 'Candidate input has an invalid or duplicate id.'
    }
    if ($candidate.fileName -isnot [string] -or
        $candidate.fileName -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
        $candidate.fileName.EndsWith('.') -or
        $candidate.fileName -imatch '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)') {
        throw "Candidate '$($candidate.id)' has an unsafe fileName."
    }
    if ($candidate.feature -isnot [string] -or [string]::IsNullOrWhiteSpace($candidate.feature) -or
        $candidate.architectures -isnot [array] -or $candidate.architectures.Count -eq 0 -or
        @($candidate.architectures | Where-Object { $_ -isnot [string] -or $_ -cnotin @('x86', 'x64', 'arm64') }).Count -gt 0 -or
        @($candidate.architectures | Sort-Object -Unique).Count -ne $candidate.architectures.Count) {
        throw "Candidate '$($candidate.id)' has invalid feature or architecture metadata."
    }
    if ($null -ne $candidate.version -and
        ($candidate.version -isnot [string] -or $candidate.version -cnotmatch '^[0-9]+(\.[0-9]+){1,3}$')) {
        throw "Candidate '$($candidate.id)' has an invalid version."
    }
    if ($null -ne $candidate.upstreamSha512 -and
        ($candidate.upstreamSha512 -isnot [string] -or $candidate.upstreamSha512 -cnotmatch '^[A-Fa-f0-9]{128}$')) {
        throw "Candidate '$($candidate.id)' has an invalid upstream SHA-512 hash."
    }
    if ($null -eq $candidate.sourceUrl) {
        $pending += [ordered]@{ id = $candidate.id; status = 'pending-canonical-source' }
        continue
    }
    if ($candidate.sourceUrl -isnot [string]) {
        throw "Candidate '$($candidate.id)' has an invalid sourceUrl; unresolved sources must be null."
    }
    Assert-ApprovedRuntimeInputUrl -SourceUrl $candidate.sourceUrl -InputId $candidate.id | Out-Null
    if (-not $fileNames.Add($candidate.fileName)) {
        throw "Candidate '$($candidate.id)' has a duplicate downloadable fileName."
    }
    $downloadable += $candidate
}

if ($ValidateOnly) {
    Write-Host "Runtime input evidence preflight passed: $($downloadable.Count) canonical sources; $($pending.Count) pending sources."
    return
}
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Runtime input evidence collection requires Windows Authenticode verification. Use -ValidateOnly for cross-platform preflight.'
}

$report = [ordered]@{
    schemaVersion = 1
    kind = 'runtime-input-evidence'
    inventorySha256 = (Get-FileHash -LiteralPath $InventoryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    inventoryAsOf = $inventory.asOf
    collectedAt = [DateTimeOffset]::UtcNow.ToString('o')
    sourceCommit = if ($env:EVIDENCE_SOURCE_SHA) { $env:EVIDENCE_SOURCE_SHA } else { $env:GITHUB_SHA }
    collectionStatus = 'partial'
    releaseReady = $false
    verified = @()
    pending = $pending
    failures = @()
}

$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) "runtime-input-evidence-$([Guid]::NewGuid())"
New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
try {
    foreach ($candidate in $downloadable) {
        # Payloads remain outside the metadata output and are never executed.
        $payload = Join-Path $temporaryDirectory "$([Guid]::NewGuid()).exe"
        try {
            Invoke-WebRequest -Uri $candidate.sourceUrl -OutFile $payload -MaximumRedirection 0 -TimeoutSec 300
            $sha512 = (Get-FileHash -LiteralPath $payload -Algorithm SHA512).Hash.ToLowerInvariant()
            if ($null -ne $candidate.upstreamSha512 -and $sha512 -cne $candidate.upstreamSha512.ToLowerInvariant()) {
                throw 'Downloaded SHA-512 does not match the upstream candidate metadata.'
            }
            $signature = Get-AuthenticodeSignature -LiteralPath $payload
            if (-not (Test-ApprovedAuthenticodeSignature -Signature $signature -ExpectedSubject 'Microsoft Corporation')) {
                throw "Microsoft Authenticode validation failed: $($signature.Status)."
            }
            $file = Get-Item -LiteralPath $payload
            $report.verified += [ordered]@{
                id = $candidate.id
                feature = $candidate.feature
                architectures = @($candidate.architectures)
                candidateVersion = $candidate.version
                observedFileVersion = $file.VersionInfo.FileVersion
                observedProductVersion = $file.VersionInfo.ProductVersion
                fileName = $candidate.fileName
                sourceUrl = $candidate.sourceUrl
                sha256 = (Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash.ToLowerInvariant()
                sha512 = $sha512
                size = $file.Length
                upstreamSha512Matched = if ($null -eq $candidate.upstreamSha512) { $null } else { $true }
                signatureStatus = [string]$signature.Status
                signerSubject = $signature.SignerCertificate.Subject
                signerThumbprint = $signature.SignerCertificate.Thumbprint
                signerNotAfter = $signature.SignerCertificate.NotAfter.ToUniversalTime().ToString('o')
            }
            Write-Host "Collected verified byte and signature evidence for $($candidate.id)."
        }
        catch {
            $report.failures += [ordered]@{ id = $candidate.id; error = $_.Exception.Message }
            Write-Warning "Evidence collection failed for $($candidate.id): $($_.Exception.Message)"
        }
        finally {
            Remove-Item -LiteralPath $payload -Force -ErrorAction SilentlyContinue
        }
    }
}
finally {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

if ($report.failures.Count -gt 0) {
    $report.collectionStatus = 'failed'
}
elseif ($pending.Count -eq 0) {
    $report.collectionStatus = 'complete'
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$reportPath = Join-Path $OutputDirectory 'evidence.json'
[IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
Write-Host "Evidence: $($report.verified.Count) verified, $($pending.Count) pending, $($report.failures.Count) failed. Report: $reportPath"
if ($report.failures.Count -gt 0) {
    throw 'Runtime input evidence collection failed; inspect the metadata report. No release lockfile was created.'
}
