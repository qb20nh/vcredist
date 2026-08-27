[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Version,

    [string]$HelperRoot = (Join-Path $PSScriptRoot '..\intermediate\helper'),
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

function Get-PeImportedDllNames {
    param([Parameter(Mandatory)][string]$Path)

    $bytes = [IO.File]::ReadAllBytes($Path)
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    $sectionCount = [BitConverter]::ToUInt16($bytes, $peOffset + 6)
    $optionalHeaderSize = [BitConverter]::ToUInt16($bytes, $peOffset + 20)
    $optionalHeaderOffset = $peOffset + 24
    $magic = [BitConverter]::ToUInt16($bytes, $optionalHeaderOffset)
    $dataDirectoryOffset = $optionalHeaderOffset + $(if ($magic -eq 0x10B) { 96 } elseif ($magic -eq 0x20B) { 112 } else { throw "'$Path' has an unsupported PE optional header." })
    $importRva = [BitConverter]::ToUInt32($bytes, $dataDirectoryOffset + 8)
    if ($importRva -eq 0) { return @() }

    $sectionTableOffset = $optionalHeaderOffset + $optionalHeaderSize
    function Convert-RvaToFileOffset([uint32]$Rva) {
        for ($index = 0; $index -lt $sectionCount; $index++) {
            $sectionOffset = $sectionTableOffset + (40 * $index)
            $virtualSize = [BitConverter]::ToUInt32($bytes, $sectionOffset + 8)
            $virtualAddress = [BitConverter]::ToUInt32($bytes, $sectionOffset + 12)
            $rawSize = [BitConverter]::ToUInt32($bytes, $sectionOffset + 16)
            $rawOffset = [BitConverter]::ToUInt32($bytes, $sectionOffset + 20)
            if ($Rva -ge $virtualAddress -and $Rva -lt ($virtualAddress + [Math]::Max($virtualSize, $rawSize))) {
                return [int]($rawOffset + $Rva - $virtualAddress)
            }
        }
        throw "'$Path' has an import RVA outside its PE sections."
    }

    $imports = [Collections.Generic.List[string]]::new()
    $descriptorOffset = Convert-RvaToFileOffset $importRva
    while ($true) {
        $nameRva = [BitConverter]::ToUInt32($bytes, $descriptorOffset + 12)
        if ($nameRva -eq 0) { break }
        $nameOffset = Convert-RvaToFileOffset $nameRva
        $end = $nameOffset
        while ($end -lt $bytes.Length -and $bytes[$end] -ne 0) { $end++ }
        if ($end -eq $bytes.Length) { throw "'$Path' has an unterminated imported DLL name." }
        $imports.Add([Text.Encoding]::ASCII.GetString($bytes, $nameOffset, $end - $nameOffset))
        $descriptorOffset += 20
    }
    return $imports
}

$machines = @{ x86 = 0x014C; x64 = 0x8664; arm64 = 0xAA64 }
$forbiddenDynamicRuntime = '^(api-ms-win-crt-|vcruntime\d+|msvcp\d+|concrt\d+|ucrtbase\.dll$)'
$knownDynamicRuntimeImports = @('vcruntime140.dll', 'msvcp140.dll', 'concrt140.dll', 'ucrtbase.dll', 'api-ms-win-crt-runtime-l1-1-0.dll')
$unmatchedKnownRuntimeImports = @($knownDynamicRuntimeImports | Where-Object { $_ -notmatch $forbiddenDynamicRuntime })
if ($unmatchedKnownRuntimeImports.Count -ne 0) {
    throw 'The MSVC runtime import guard does not match all known dynamic runtime DLL names.'
}
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
    $dynamicRuntimeImports = Get-PeImportedDllNames -Path $helper | Where-Object { $_ -match $forbiddenDynamicRuntime }
    if ($dynamicRuntimeImports) {
        throw "'$helper' dynamically depends on the MSVC runtime: $($dynamicRuntimeImports -join ', ')."
    }
}

$selfTest = Join-Path $HelperRoot 'x64\RuntimePack.NetFx35Enabler.exe'
$selfTestProcess = Start-Process -FilePath $selfTest -ArgumentList '--self-test' -Wait -PassThru
if ($selfTestProcess.ExitCode -ne 0) { throw "NetFx3 helper self-test failed with exit code $($selfTestProcess.ExitCode)." }

$invalidInvocations = @(
    @{ Name = 'self-test suffix'; Arguments = @('--self-test-extra') },
    @{ Name = 'misspelled enable option'; Arguments = @('--enabel') },
    @{ Name = 'additional argument'; Arguments = @('--enable', '--unexpected') }
)
foreach ($invocation in $invalidInvocations) {
    $process = Start-Process -FilePath $selfTest -ArgumentList $invocation.Arguments -Wait -PassThru
    if ($process.ExitCode -ne 87) {
        throw "NetFx3 helper returned $($process.ExitCode) for the $($invocation.Name) invocation; expected ERROR_INVALID_PARAMETER (87) without enabling NetFx3."
    }
}
Write-Host 'Native helper and WiX bundle architecture checks passed.'
