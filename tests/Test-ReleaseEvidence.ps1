[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$evidenceScript = Join-Path $PSScriptRoot '..\tools\New-ReleaseEvidence.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) "release-evidence-$([guid]::NewGuid())"
$lockFile = Join-Path $root 'lock.json'
$architectures = @('x86', 'x64', 'arm64')
$modes = @('Bootstrap', 'Standalone')
$version = '1.2.3'

function New-ArtifactSet {
    param([Parameter(Mandatory)][string[]]$Names)

    $artifactDirectory = Join-Path $root ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $artifactDirectory | Out-Null
    foreach ($name in $Names) {
        [IO.File]::WriteAllText((Join-Path $artifactDirectory $name), $name)
    }
    return $artifactDirectory
}

function Assert-Rejected {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string[]]$ArtifactNames)

    $artifactDirectory = New-ArtifactSet -Names $ArtifactNames
    try {
        & $evidenceScript -LockFile $lockFile -ArtifactDirectory $artifactDirectory -OutputDirectory (Join-Path $artifactDirectory 'evidence') -Version "v$version"
    }
    catch {
        return
    }
    throw "The '$Name' artifact set was accepted unexpectedly."
}

try {
    New-Item -ItemType Directory -Path $root | Out-Null
    @{
        schemaVersion = 1
        inputs = @(@{
            id = 'fixture'; version = '1.0'; sourceUrl = 'https://example.invalid/input.exe'
            sha256 = ('a' * 64)
        })
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $lockFile

    $validNames = @(
        foreach ($architecture in $architectures) {
            foreach ($mode in $modes) {
                "RuntimePack-$version-$architecture-$mode.exe"
            }
        }
    )
    $validNames[0] = $validNames[0] -ireplace '\.exe$', '.EXE'
    $validDirectory = New-ArtifactSet -Names $validNames
    $validOutput = Join-Path $validDirectory 'evidence'
    & $evidenceScript -LockFile $lockFile -ArtifactDirectory $validDirectory -OutputDirectory $validOutput -Version "v$version"
    $metadata = Get-Content -LiteralPath (Join-Path $validOutput 'release-metadata.json') -Raw | ConvertFrom-Json
    if ($metadata.bundleCount -ne 6 -or @($metadata.bundles.architecture | Sort-Object -Unique).Count -ne 3 -or @($metadata.bundles.mode | Sort-Object -Unique).Count -ne 2) {
        throw 'Valid release metadata does not describe the complete architecture/mode matrix.'
    }

    Assert-Rejected -Name 'six unrelated files' -ArtifactNames @(1..6 | ForEach-Object { "unrelated-$_.exe" })
    Assert-Rejected -Name 'duplicated mode with another mode missing' -ArtifactNames @(
        'RuntimePack-1.2.3-x86-Bootstrap.exe',
        'RuntimePack-1.2.3-x64-Bootstrap.exe',
        'RuntimePack-1.2.3-arm64-Bootstrap.exe',
        'RuntimePack-1.2.3-x86-Bootstrap-copy.exe',
        'RuntimePack-1.2.3-x64-Standalone.exe',
        'RuntimePack-1.2.3-arm64-Standalone.exe'
    )
    Assert-Rejected -Name 'stale version' -ArtifactNames @($validNames -replace '1\.2\.3', '1.2.2')
    Write-Host 'Release evidence filename matrix checks passed.'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
