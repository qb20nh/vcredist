$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$collector = Join-Path $PSScriptRoot '..\tools\Get-RuntimeInputEvidence.ps1'
. (Join-Path $PSScriptRoot '..\tools\RuntimeInputLock.ps1')
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) "runtime-input-evidence-tests-$([Guid]::NewGuid())"
New-Item -ItemType Directory -Path $testDirectory | Out-Null

function New-TestInventory {
    return [pscustomobject]@{
        schemaVersion = 1
        kind = 'runtime-input-candidates'
        asOf = '2026-10-20'
        inputs = @(
            [pscustomobject]@{
                id = 'runtime-x64'
                feature = 'vc-redist-v14'
                architectures = @('x64')
                version = $null
                fileName = 'runtime-x64.exe'
                sourceUrl = 'https://download.microsoft.com/validation-only.exe'
                upstreamSha512 = ('a' * 128)
            },
            [pscustomobject]@{
                id = 'unresolved-x86'
                feature = 'vc-redist-v14'
                architectures = @('x86')
                version = $null
                fileName = 'unresolved-x86.exe'
                sourceUrl = $null
                upstreamSha512 = $null
            }
        )
    }
}

function Write-TestInventory([object]$Inventory) {
    $path = Join-Path $testDirectory 'candidates.json'
    [IO.File]::WriteAllText($path, ($Inventory | ConvertTo-Json -Depth 10))
    return $path
}

function Assert-PreflightRejects {
    param([string]$Description, [scriptblock]$Mutate, [string]$ExpectedPattern)

    $inventory = New-TestInventory
    & $Mutate $inventory
    $path = Write-TestInventory $inventory
    try {
        & $collector -InventoryPath $path -OutputDirectory (Join-Path $testDirectory 'output') -ValidateOnly
        throw "$Description was accepted."
    }
    catch {
        if ($_.Exception.Message -eq "$Description was accepted.") { throw }
        if ($_.Exception.Message -notmatch $ExpectedPattern) {
            throw "$Description failed unexpectedly: $($_.Exception.Message)"
        }
    }
    if (Test-Path -LiteralPath (Join-Path $testDirectory 'output')) {
        throw 'Preflight unexpectedly created an evidence output directory.'
    }
}

try {
    $path = Write-TestInventory (New-TestInventory)
    & $collector -InventoryPath $path -OutputDirectory (Join-Path $testDirectory 'output') -ValidateOnly
    if (Test-Path -LiteralPath (Join-Path $testDirectory 'output')) {
        throw 'Successful preflight unexpectedly created an evidence output directory.'
    }
    $sharedInstaller = New-TestInventory
    $sharedInstaller.inputs[0].architectures = @('x86', 'x64', 'arm64')
    & $collector -InventoryPath (Write-TestInventory $sharedInstaller) -ValidateOnly

    Assert-PreflightRejects 'A release inventory kind' { param($inventory) $inventory.kind = 'runtime-input-lock' } 'Expected a version 1'
    Assert-PreflightRejects 'An array inventory kind' { param($inventory) $inventory.kind = @('runtime-input-candidates') } 'Expected a version 1'
    Assert-PreflightRejects 'A string schema version' { param($inventory) $inventory.schemaVersion = '1' } 'Expected a version 1'
    Assert-PreflightRejects 'An unapproved download host' { param($inventory) $inventory.inputs[0].sourceUrl = 'https://example.invalid/runtime.exe' } 'approved canonical Microsoft HTTPS URL'
    Assert-PreflightRejects 'A credential-bearing URL' { param($inventory) $inventory.inputs[0].sourceUrl = 'https://user:password@download.microsoft.com/runtime.exe' } 'without embedded credentials'
    Assert-PreflightRejects 'An HTTP source' { param($inventory) $inventory.inputs[0].sourceUrl = 'http://download.microsoft.com/runtime.exe' } 'approved canonical Microsoft HTTPS URL'
    Assert-PreflightRejects 'An unresolved empty-string source' { param($inventory) $inventory.inputs[1].sourceUrl = '' } 'approved canonical Microsoft HTTPS URL'
    Assert-PreflightRejects 'A malformed source type' { param($inventory) $inventory.inputs[0].sourceUrl = 1 } 'invalid sourceUrl'
    Assert-PreflightRejects 'A malformed upstream digest' { param($inventory) $inventory.inputs[0].upstreamSha512 = 'not-a-digest' } 'invalid upstream SHA-512'
    Assert-PreflightRejects 'A path traversal filename' { param($inventory) $inventory.inputs[0].fileName = '../runtime.exe' } 'unsafe fileName'
    Assert-PreflightRejects 'A reserved Windows filename' { param($inventory) $inventory.inputs[0].fileName = 'CON.exe' } 'unsafe fileName'
    Assert-PreflightRejects 'A duplicate id' { param($inventory) $inventory.inputs[1].id = $inventory.inputs[0].id } 'invalid or duplicate id'
    Assert-PreflightRejects 'A duplicate downloadable filename' {
        param($inventory)
        $inventory.inputs[1].sourceUrl = 'https://download.microsoft.com/other-validation-only.exe'
        $inventory.inputs[1].fileName = 'RUNTIME-X64.EXE'
    } 'duplicate downloadable fileName'
    Assert-PreflightRejects 'An invalid architecture set' { param($inventory) $inventory.inputs[0].architectures = @('x64', 'arm32') } 'invalid feature or architecture'
    Assert-PreflightRejects 'A duplicate architecture' { param($inventory) $inventory.inputs[0].architectures = @('x64', 'x64') } 'invalid feature or architecture'
    Assert-PreflightRejects 'An empty candidate set' { param($inventory) $inventory.inputs = @() } 'nonempty inputs array'

    $path = Write-TestInventory (New-TestInventory)
    try {
        Read-RuntimeInputLock -Path $path | Out-Null
        throw 'A candidate inventory was accepted as a release lockfile.'
    }
    catch {
        if ($_.Exception.Message -notmatch "missing required property 'supportedDotnetCycles'") { throw }
    }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        try {
            & $collector -InventoryPath $path -OutputDirectory (Join-Path $testDirectory 'output')
            throw 'Collection ran without Windows Authenticode.'
        }
        catch {
            if ($_.Exception.Message -notmatch 'requires Windows Authenticode verification') { throw }
        }
        if (Test-Path -LiteralPath (Join-Path $testDirectory 'output')) {
            throw 'Unsupported-platform collection created an output directory.'
        }
    }
    else {
        $originalSourceSha = $env:EVIDENCE_SOURCE_SHA
        $originalGitHubSha = $env:GITHUB_SHA
        try {
            $env:GITHUB_SHA = 'a' * 40
            $inventory = New-TestInventory
            foreach ($candidate in $inventory.inputs) { $candidate.sourceUrl = $null }
            $path = Write-TestInventory $inventory
            $reportDirectory = Join-Path $testDirectory 'source-report'
            foreach ($case in @(
                @{ source = ('b' * 40); expected = ('b' * 40) },
                @{ source = ''; expected = ('a' * 40) },
                @{ source = $null; expected = ('a' * 40) }
            )) {
                $env:EVIDENCE_SOURCE_SHA = $case.source
                & $collector -InventoryPath $path -OutputDirectory $reportDirectory
                $report = Get-Content -LiteralPath (Join-Path $reportDirectory 'evidence.json') -Raw | ConvertFrom-Json
                if ($report.sourceCommit -cne $case.expected) {
                    throw "Evidence source commit mismatch: expected '$($case.expected)', got '$($report.sourceCommit)'."
                }
            }
        }
        finally {
            $env:EVIDENCE_SOURCE_SHA = $originalSourceSha
            $env:GITHUB_SHA = $originalGitHubSha
        }
    }
    Write-Host 'Runtime input evidence preflight tests passed.'
}
finally {
    Remove-Item -LiteralPath $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
