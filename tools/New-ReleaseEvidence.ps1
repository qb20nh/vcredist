[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$LockFile,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$ArtifactDirectory,

    [Parameter(Mandatory)]
    [string]$OutputDirectory,

    [Parameter(Mandatory)]
    [string]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$lock = Get-Content -LiteralPath $LockFile -Raw | ConvertFrom-Json
if ($lock.schemaVersion -ne 1 -or $null -eq $lock.inputs -or $lock.inputs.Count -eq 0) {
    throw 'A populated version 1 input lockfile is required for release evidence.'
}

$bundleVersion = $Version -replace '^v', ''
if ([string]::IsNullOrWhiteSpace($bundleVersion)) {
    throw 'Version must contain a value after an optional leading v.'
}

$expectedBundles = @(
    foreach ($architecture in @('x86', 'x64', 'arm64')) {
        foreach ($mode in @('Bootstrap', 'Standalone')) {
            [pscustomobject]@{
                name = "RuntimePack-$bundleVersion-$architecture-$mode.exe"
                architecture = $architecture
                mode = $mode
            }
        }
    }
)
$artifacts = @(Get-ChildItem -LiteralPath $ArtifactDirectory -File | Where-Object Extension -IEQ '.exe' | Sort-Object Name)
$actualNames = @($artifacts | ForEach-Object { $_.Name -ireplace '\.exe$', '.exe' })
$expectedNames = @($expectedBundles | ForEach-Object name)
$missing = @($expectedNames | Where-Object { $actualNames -cnotcontains $_ })
$unexpected = @($actualNames | Where-Object { $expectedNames -cnotcontains $_ })
$duplicates = @($actualNames | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
if ($missing.Count -ne 0 -or $unexpected.Count -ne 0 -or $duplicates.Count -ne 0) {
    $problems = @()
    if ($missing.Count -ne 0) { $problems += "missing: $($missing -join ', ')" }
    if ($unexpected.Count -ne 0) { $problems += "unexpected: $($unexpected -join ', ')" }
    if ($duplicates.Count -ne 0) { $problems += "duplicate: $($duplicates -join ', ')" }
    throw "Release bundle filenames do not match the expected architecture/mode matrix ($($problems -join '; '))."
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$checksums = foreach ($artifact in $artifacts) {
    $hash = (Get-FileHash -LiteralPath $artifact.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash *$($artifact.Name)"
}
$checksumFile = Join-Path $OutputDirectory 'SHA256SUMS.txt'
[IO.File]::WriteAllLines($checksumFile, [string[]]$checksums, [Text.UTF8Encoding]::new($false))

$packages = foreach ($input in $lock.inputs | Sort-Object id) {
    [ordered]@{
        SPDXID = "SPDXRef-Input-$($input.id -replace '[^A-Za-z0-9.-]', '-')"
        name = $input.id
        versionInfo = $input.version
        downloadLocation = $input.sourceUrl
        checksums = @([ordered]@{ algorithm = 'SHA256'; checksumValue = $input.sha256.ToLowerInvariant() })
        licenseConcluded = 'NOASSERTION'
        supplier = 'Organization: Microsoft Corporation'
        externalRefs = @([ordered]@{ referenceCategory = 'OTHER'; referenceType = 'purl'; referenceLocator = "pkg:generic/microsoft-runtime/$($input.id)@$($input.version)" })
    }
}
$sbom = [ordered]@{
    spdxVersion = 'SPDX-2.3'
    dataLicense = 'CC0-1.0'
    SPDXID = 'SPDXRef-DOCUMENT'
    name = "Runtime-Pack-Verified-$Version"
    documentNamespace = "https://github.com/qb20nh/vcredist/releases/download/$Version/sbom.spdx.json"
    creationInfo = [ordered]@{ creators = @('Tool: Runtime Pack Verified New-ReleaseEvidence.ps1'); created = [DateTime]::UtcNow.ToString('o') }
    packages = @($packages)
}
$sbomFile = Join-Path $OutputDirectory 'sbom.spdx.json'
[IO.File]::WriteAllText($sbomFile, ($sbom | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))

$metadata = [ordered]@{
    version = $Version
    bundleCount = $artifacts.Count
    inputLockSha256 = (Get-FileHash -LiteralPath $LockFile -Algorithm SHA256).Hash.ToLowerInvariant()
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    bundles = @($artifacts | ForEach-Object {
        $canonicalName = $_.Name -ireplace '\.exe$', '.exe'
        $bundle = $expectedBundles | Where-Object name -CEQ $canonicalName
        [ordered]@{
            name = $_.Name
            architecture = $bundle.architecture
            mode = $bundle.mode
            size = $_.Length
        }
    })
}
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'release-metadata.json'), ($metadata | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
