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

$artifacts = @(Get-ChildItem -LiteralPath $ArtifactDirectory -Filter '*.exe' -File | Sort-Object Name)
if ($artifacts.Count -ne 6) {
    throw "Expected exactly six bundles (three architectures times two modes); found $($artifacts.Count)."
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
    bundles = @($artifacts | ForEach-Object { [ordered]@{ name = $_.Name; size = $_.Length } })
}
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'release-metadata.json'), ($metadata | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
