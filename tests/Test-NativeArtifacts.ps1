[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Version,

    [string]$HelperRoot = (Join-Path $PSScriptRoot '..\artifacts\helper'),
    [string]$BundleRoot = (Join-Path $PSScriptRoot '..\src\Bundle\bin\Release')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PeMachine {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [IO.File]::OpenRead($Path)
    try {
        $reader = [IO.BinaryReader]::new($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) { throw "'$Path' is not an MZ executable." }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) { throw "'$Path' is not a PE executable." }
        return $reader.ReadUInt16()
    }
    finally {
        $stream.Dispose()
    }
}

$machines = @{ x86 = 0x014C; x64 = 0x8664; arm64 = 0xAA64 }
foreach ($architecture in $machines.Keys) {
    $helper = Join-Path $HelperRoot "$architecture\RuntimePack.NetFx35Enabler.exe"
    $bundle = Join-Path $BundleRoot "$architecture\Bootstrap\RuntimePack-$Version-$architecture-Bootstrap.exe"
    foreach ($path in $helper, $bundle) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Expected native artifact '$path' is missing." }
        $actual = Get-PeMachine -Path $path
        if ($actual -ne $machines[$architecture]) {
            throw "'$path' has PE machine 0x$($actual.ToString('X4')); expected $architecture."
        }
    }
}

$selfTest = Join-Path $HelperRoot 'x64\RuntimePack.NetFx35Enabler.exe'
$selfTestProcess = Start-Process -FilePath $selfTest -ArgumentList '--self-test' -Wait -PassThru
if ($selfTestProcess.ExitCode -ne 0) { throw "NetFx3 helper self-test failed with exit code $($selfTestProcess.ExitCode)." }
Write-Host 'Native helper and WiX bundle architecture checks passed.'
