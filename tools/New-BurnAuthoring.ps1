[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Bootstrap', 'Standalone')]
    [string]$Mode,

    [Parameter(Mandatory)]
    [ValidateSet('x86', 'x64', 'arm64')]
    [string]$Architecture,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$LockFile,

    [Parameter(Mandatory)]
    [string]$OutputFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'RuntimeInputPolicy.psm1') -Force

function Escape-Xml([object]$Value) {
    return [Security.SecurityElement]::Escape([string]$Value)
}

function Feature-Variable([string]$Feature) {
    switch ($Feature) {
        'vc-redist-v14' { return 'Feature_VcRedistV14' }
        'dotnet-desktop' { return 'Feature_DotNetDesktop' }
        'dotnet-aspnet' { return 'Feature_DotNetAspNet' }
        'dotnet-framework' { return 'Feature_DotNetFramework' }
        'dotnet-framework-35' { return 'Feature_DotNetFramework35' }
        'directx-legacy' { return 'Feature_DirectXLegacy' }
        default { throw "Unknown feature '$Feature'." }
    }
}

function Wix-Identifier([string]$Value) {
    return 'P_' + ($Value -replace '[^A-Za-z0-9_.]', '_')
}

$lock = Get-Content -LiteralPath $LockFile -Raw | ConvertFrom-Json
if ($lock.schemaVersion -ne 1 -or $null -eq $lock.inputs -or $lock.inputs.Count -eq 0) {
    throw "'$LockFile' is not a populated version 1 lockfile."
}

$selected = @($lock.inputs | Where-Object { $_.architecture -eq $Architecture } | Sort-Object feature, cycle, id)
if ($selected.Count -eq 0) {
    throw "The lockfile has no '$Architecture' inputs."
}
if ($Architecture -eq 'arm64' -and @($selected | Where-Object feature -eq 'directx-legacy').Count -gt 0) {
    throw 'DirectX June 2010 must not be authored for ARM64 without a reviewed ARM64 package.'
}

# Validate the complete selection before opening the output. A bad later entry
# must never leave behind a syntactically usable, partially authored fragment.
foreach ($input in $selected) {
    foreach ($field in 'id', 'feature', 'fileName', 'sourceUrl', 'sha256', 'sha512', 'size', 'version', 'signerSubjectContains', 'installArguments', 'detectCondition', 'licenseUrl') {
        if ([string]::IsNullOrWhiteSpace([string]$input.PSObject.Properties[$field].Value)) {
            throw "Input '$($input.id)' has no '$field'."
        }
    }
    if ($input.id -like 'example-*') { throw "Example input '$($input.id)' cannot be authored." }
    if ($input.fileName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw "Unsafe file name for '$($input.id)'."
    }
    Feature-Variable $input.feature | Out-Null
    Assert-ApprovedRuntimeInputUrl -SourceUrl $input.sourceUrl -InputId $input.id | Out-Null
}

$outputDirectory = Split-Path -Parent $OutputFile
if (-not [string]::IsNullOrEmpty($outputDirectory)) {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}

$writerSettings = [Xml.XmlWriterSettings]::new()
$writerSettings.Indent = $true
$writerSettings.Encoding = [Text.UTF8Encoding]::new($false)
$writer = [Xml.XmlWriter]::Create($OutputFile, $writerSettings)
try {
    $writer.WriteStartDocument()
    $writer.WriteStartElement('Wix', 'http://wixtoolset.org/schemas/v4/wxs')
    $writer.WriteStartElement('Fragment')
    $writer.WriteStartElement('PackageGroup')
    $writer.WriteAttributeString('Id', 'RuntimeInputs')

    foreach ($input in $selected) {
        $writer.WriteStartElement('ExePackage')
        $packageId = Wix-Identifier $input.id
        $writer.WriteAttributeString('Id', $packageId)
        $writer.WriteAttributeString('PerMachine', 'yes')
        $writer.WriteAttributeString('Permanent', 'yes')
        $writer.WriteAttributeString('Vital', 'yes')
        $writer.WriteAttributeString('InstallArguments', $input.installArguments)
        $writer.WriteAttributeString('RepairArguments', $input.installArguments)
        $writer.WriteAttributeString('DetectCondition', $input.detectCondition)
        $writer.WriteAttributeString('InstallCondition', (Feature-Variable $input.feature))

        if ($Mode -eq 'Bootstrap') {
            $writer.WriteStartElement('ExePackagePayload')
            $writer.WriteAttributeString('Id', "$packageId`_payload")
            $writer.WriteAttributeString('Name', $input.fileName)
            $writer.WriteAttributeString('DownloadUrl', $input.sourceUrl)
            $writer.WriteAttributeString('Hash', $input.sha512)
            $writer.WriteAttributeString('Size', [string]$input.size)
            $writer.WriteAttributeString('Version', $input.version)
            $writer.WriteEndElement()
        }
        else {
            $writer.WriteAttributeString('SourceFile', "`$(var.RuntimeInputsDirectory)\$($input.fileName)")
        }
        $writer.WriteEndElement()
    }

    $writer.WriteEndElement()
    $writer.WriteEndElement()
    $writer.WriteEndElement()
    $writer.WriteEndDocument()
}
finally {
    $writer.Dispose()
}
