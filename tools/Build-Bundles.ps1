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
$helperSource = Join-Path $root 'src\NetFx35Enabler'
$dotnet = Join-Path ${env:ProgramFiles} 'dotnet\dotnet.exe'
if (-not (Test-Path -LiteralPath $dotnet -PathType Leaf)) { throw 'The .NET SDK is required to build source, but is never bundled in releases.' }
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) { throw 'Visual Studio Installer discovery tool (vswhere) is required.' }
$vsInstallPath = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
if ([string]::IsNullOrWhiteSpace($vsInstallPath)) { throw 'Visual Studio C++ Build Tools are required to build the open-source NetFx3 helper.' }
$vsDevCmd = Join-Path $vsInstallPath 'Common7\Tools\VsDevCmd.bat'
$cmake = Join-Path $vsInstallPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
if (-not (Test-Path -LiteralPath $vsDevCmd -PathType Leaf) -or -not (Test-Path -LiteralPath $cmake -PathType Leaf)) {
    throw 'Visual Studio Build Tools with C++ and CMake are required to build the open-source NetFx3 helper.'
}

function Build-NetFx35Enabler {
    param([ValidateSet('x86', 'x64', 'arm64')][string]$Architecture)

    $buildDirectory = Join-Path $helperSource "build\$Architecture"
    $outputDirectory = Join-Path $root "artifacts\helper\$Architecture"
    $output = Join-Path $outputDirectory 'RuntimePack.NetFx35Enabler.exe'
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

    $command = "call `"$vsDevCmd`" -arch=$Architecture -host_arch=x64 && `"$cmake`" -S `"$helperSource`" -B `"$buildDirectory`" -G `"NMake Makefiles`" -DCMAKE_BUILD_TYPE=Release -DCMAKE_RUNTIME_OUTPUT_DIRECTORY=`"$outputDirectory`" && `"$cmake`" --build `"$buildDirectory`""
    & cmd.exe /d /c $command | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output -PathType Leaf)) {
        throw "Native NetFx3 helper build failed for $Architecture."
    }
    return $output
}

$modes = if ($Mode -eq 'Both') { @('Bootstrap', 'Standalone') } else { @($Mode) }
$architectures = if ($Architecture -eq 'All') { @('x86', 'x64', 'arm64') } else { @($Architecture) }

foreach ($currentMode in $modes) {
    if ($currentMode -eq 'Standalone') {
        & (Join-Path $PSScriptRoot 'Resolve-VerifiedInputs.ps1') -LockFile $LockFile -Destination $RuntimeInputsDirectory
        if ($LASTEXITCODE -ne 0) { throw 'Verified input staging failed.' }
    }

    foreach ($currentArchitecture in $architectures) {
        $helper = Build-NetFx35Enabler -Architecture $currentArchitecture
        & $dotnet build $project --configuration $Configuration "-p:BundleMode=$currentMode" "-p:TargetArchitecture=$currentArchitecture" "-p:BundleVersion=$Version" "-p:RuntimeInputLockFile=$LockFile" "-p:RuntimeInputsDirectory=$RuntimeInputsDirectory" "-p:NetFx35HelperPath=$helper"
        if ($LASTEXITCODE -ne 0) { throw "WiX build failed for $currentMode/$currentArchitecture." }
    }
}
