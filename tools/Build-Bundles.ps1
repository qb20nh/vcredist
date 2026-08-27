[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$LockFile,

    [Parameter(Mandatory)]
    [ValidateSet('Bootstrap', 'Standalone', 'Both')]
    [string]$Mode,

    [Parameter(Mandatory)]
    [ValidateSet('x86', 'x64', 'arm64', 'All')]
    [string]$Architecture,

    [string]$RuntimeInputsDirectory = (Join-Path $PSScriptRoot '..\inputs'),
    [string]$Version = '0.1.0',
    [string]$Configuration = 'Release'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$project = Join-Path $root 'src\Bundle\RuntimePack.Bundle.wixproj'
$dotnet = Join-Path ${env:ProgramFiles} 'dotnet\dotnet.exe'
if (-not (Test-Path -LiteralPath $dotnet -PathType Leaf)) { throw 'The .NET SDK is required to build source, but is never bundled in releases.' }

$modes = if ($Mode -eq 'Both') { @('Bootstrap', 'Standalone') } else { @($Mode) }
$architectures = if ($Architecture -eq 'All') { @('x86', 'x64', 'arm64') } else { @($Architecture) }

foreach ($currentMode in $modes) {
    if ($currentMode -eq 'Standalone') {
        & (Join-Path $PSScriptRoot 'Resolve-VerifiedInputs.ps1') -LockFile $LockFile -Destination $RuntimeInputsDirectory
        if ($LASTEXITCODE -ne 0) { throw 'Verified input staging failed.' }
    }

    foreach ($currentArchitecture in $architectures) {
        & $dotnet build $project --configuration $Configuration "-p:BundleMode=$currentMode" "-p:TargetArchitecture=$currentArchitecture" "-p:BundleVersion=$Version" "-p:RuntimeInputLockFile=$LockFile" "-p:RuntimeInputsDirectory=$RuntimeInputsDirectory"
        if ($LASTEXITCODE -ne 0) { throw "WiX build failed for $currentMode/$currentArchitecture." }
    }
}
