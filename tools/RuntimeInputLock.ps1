Set-StrictMode -Version Latest

$script:ApprovedSignerSubject = 'Microsoft Corporation'
$script:ApprovedSourceHosts = @(
    'download.microsoft.com',
    'download.windowsupdate.com',
    'download.visualstudio.microsoft.com',
    'dotnetcli.blob.core.windows.net',
    'builds.dotnet.microsoft.com'
)

function Test-LockProperty {
    param([object]$Object, [string]$Name, [string]$Context)

    return @($Object.PSObject.Properties | Where-Object { $_.Name -ceq $Name }).Count -eq 1
}

function Assert-LockProperty {
    param([object]$Object, [string]$Name, [string]$Context)

    if (-not (Test-LockProperty -Object $Object -Name $Name -Context $Context)) {
        throw "$Context is missing required property '$Name'."
    }
}

function Assert-HttpsUri {
    param([string]$Value, [string]$Field, [string]$Context, [switch]$RequireApprovedHost)

    $uri = $null
    if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -cne 'https') {
        throw "$Context has an invalid '$Field'; an absolute HTTPS URL is required."
    }
    if (-not [string]::IsNullOrEmpty($uri.UserInfo)) {
        throw "$Context has an invalid '$Field'; embedded URL credentials are not allowed."
    }
    if ($RequireApprovedHost -and $script:ApprovedSourceHosts -notcontains $uri.IdnHost.ToLowerInvariant()) {
        throw "$Context has an unapproved '$Field' host."
    }
}

function Test-JsonInteger {
    param([object]$Value)

    return $Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64]
}

function Read-RuntimeInputLock {
    param([Parameter(Mandatory)][string]$Path)

    try { $lock = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { throw "'$Path' is not valid JSON: $($_.Exception.Message)" }

    foreach ($name in 'schemaVersion', 'supportedDotnetCycles', 'inputs') {
        Assert-LockProperty $lock $name "Lockfile '$Path'"
    }
    $rootNames = @($lock.PSObject.Properties.Name)
    if (@($rootNames | Where-Object { $_ -cnotin @('schemaVersion', 'supportedDotnetCycles', 'inputs') }).Count) {
        throw "Lockfile '$Path' contains unsupported properties."
    }
    if (-not (Test-JsonInteger $lock.schemaVersion) -or $lock.schemaVersion -ne 1) { throw "'$Path' is not a version 1 lockfile." }
    if ($lock.supportedDotnetCycles -isnot [array]) { throw "'$Path' has invalid supportedDotnetCycles." }
    $cycles = @($lock.supportedDotnetCycles)
    if (@($cycles | Where-Object { $_ -isnot [string] -or $_ -cnotin @('8', '9', '10') }).Count -or
        @($cycles | Sort-Object -Unique).Count -ne $cycles.Count) { throw "'$Path' has invalid supportedDotnetCycles." }
    if ($lock.inputs -isnot [array]) { throw "'$Path' has an invalid inputs collection." }
    $inputs = @($lock.inputs)
    if ($inputs.Count -eq 0) { throw "'$Path' has no runtime inputs." }

    $required = @('id', 'feature', 'architecture', 'fileName', 'sourceUrl', 'sha256', 'sha512', 'size', 'version', 'signerSubjectContains', 'installArguments', 'detectCondition', 'licenseUrl')
    $allowed = $required + @('cycle', 'inPlaceRank')
    $features = @('vc-redist-v14', 'dotnet-desktop', 'dotnet-aspnet', 'dotnet-framework', 'dotnet-framework-35', 'directx-legacy')
    foreach ($runtimeInput in $inputs) {
        $context = "Runtime input '$($runtimeInput.id)'"
        foreach ($name in $required) { Assert-LockProperty $runtimeInput $name $context }
        if (@($runtimeInput.PSObject.Properties.Name | Where-Object { $_ -cnotin $allowed }).Count) { throw "$context contains unsupported properties." }
        if ($runtimeInput.id -isnot [string] -or $runtimeInput.id -cnotmatch '^[a-z0-9][a-z0-9-]*$' -or $runtimeInput.id -clike 'example-*') { throw "$context has an invalid id." }
        if ($runtimeInput.feature -isnot [string] -or $runtimeInput.feature -cnotin $features) { throw "$context has an invalid feature." }
        if ($runtimeInput.architecture -isnot [string] -or $runtimeInput.architecture -cnotin @('x86', 'x64', 'arm64')) { throw "$context has an invalid architecture." }
        if ($runtimeInput.fileName -isnot [string] -or $runtimeInput.fileName -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "$context has an unsafe fileName." }
        if ($runtimeInput.sourceUrl -isnot [string]) { throw "$context has an invalid sourceUrl." }
        if ($runtimeInput.licenseUrl -isnot [string]) { throw "$context has an invalid licenseUrl." }
        Assert-HttpsUri $runtimeInput.sourceUrl 'sourceUrl' $context -RequireApprovedHost
        Assert-HttpsUri $runtimeInput.licenseUrl 'licenseUrl' $context
        if ($runtimeInput.sha256 -isnot [string] -or $runtimeInput.sha256 -cnotmatch '^[A-Fa-f0-9]{64}$') { throw "$context has an invalid SHA-256 hash." }
        if ($runtimeInput.sha512 -isnot [string] -or $runtimeInput.sha512 -cnotmatch '^[A-Fa-f0-9]{128}$') { throw "$context has an invalid SHA-512 hash." }
        if (-not (Test-JsonInteger $runtimeInput.size) -or $runtimeInput.size -lt 1) { throw "$context has an invalid size." }
        if ($runtimeInput.version -isnot [string] -or $runtimeInput.version -cnotmatch '^[0-9]+(\.[0-9]+){1,3}$') { throw "$context has an invalid version." }
        if ($runtimeInput.signerSubjectContains -isnot [string] -or $runtimeInput.signerSubjectContains -cne $script:ApprovedSignerSubject) { throw "$context has an unapproved signerSubjectContains value." }
        if ($runtimeInput.installArguments -isnot [string]) { throw "$context has invalid installArguments." }
        if ($runtimeInput.detectCondition -isnot [string] -or [string]::IsNullOrEmpty($runtimeInput.detectCondition)) { throw "$context has an invalid detectCondition." }
        if ($runtimeInput.feature -cin @('dotnet-desktop', 'dotnet-aspnet')) {
            Assert-LockProperty $runtimeInput 'cycle' $context
        }
        if ((Test-LockProperty $runtimeInput 'cycle' $context) -and ($runtimeInput.cycle -isnot [string] -or $runtimeInput.cycle -cnotin $cycles)) { throw "$context has an invalid cycle." }
        if ($runtimeInput.feature -ceq 'dotnet-framework') { Assert-LockProperty $runtimeInput 'inPlaceRank' $context }
        if ((Test-LockProperty $runtimeInput 'inPlaceRank' $context) -and (-not (Test-JsonInteger $runtimeInput.inPlaceRank) -or $runtimeInput.inPlaceRank -lt 1)) { throw "$context has an invalid inPlaceRank." }
    }
    return $lock
}

function Test-ApprovedSignerSubject {
    param([string]$Expected, [string]$Actual)

    if ($Expected -cne $script:ApprovedSignerSubject -or [string]::IsNullOrEmpty($Actual)) {
        return $false
    }

    try {
        $rawData = [Security.Cryptography.X509Certificates.X500DistinguishedName]::new($Actual).RawData
        $offset = 0
        $name = Read-DerElement -Data $rawData -Offset ([ref]$offset) -End $rawData.Length
        if ($name.Tag -ne 0x30 -or $name.End -ne $rawData.Length) { return $false }

        $organizationValues = @()
        $relativeNameOffset = $name.ValueOffset
        while ($relativeNameOffset -lt $name.End) {
            $relativeName = Read-DerElement -Data $rawData -Offset ([ref]$relativeNameOffset) -End $name.End
            if ($relativeName.Tag -ne 0x31) { return $false }

            $attributeOffset = $relativeName.ValueOffset
            while ($attributeOffset -lt $relativeName.End) {
                $attribute = Read-DerElement -Data $rawData -Offset ([ref]$attributeOffset) -End $relativeName.End
                if ($attribute.Tag -ne 0x30) { return $false }

                $componentOffset = $attribute.ValueOffset
                $oid = Read-DerElement -Data $rawData -Offset ([ref]$componentOffset) -End $attribute.End
                $value = Read-DerElement -Data $rawData -Offset ([ref]$componentOffset) -End $attribute.End
                if ($oid.Tag -ne 0x06 -or $componentOffset -ne $attribute.End) { return $false }

                if (Test-DerBytes -Data $rawData -Offset $oid.ValueOffset -Length $oid.Length -Expected @(0x55, 0x04, 0x0A)) {
                    $organizationValues += ConvertFrom-DerDirectoryString -Data $rawData -Element $value
                }
            }
        }

        return $organizationValues.Count -eq 1 -and $organizationValues[0] -ceq $script:ApprovedSignerSubject
    }
    catch {
        return $false
    }
}

function Read-DerElement {
    param([byte[]]$Data, [ref]$Offset, [int]$End)

    if ($Offset.Value -ge $End) { throw 'Unexpected end of DER input.' }
    $tag = $Data[$Offset.Value]
    $Offset.Value++
    if ($Offset.Value -ge $End) { throw 'DER element has no length.' }

    $firstLengthByte = $Data[$Offset.Value]
    $Offset.Value++
    if ($firstLengthByte -lt 0x80) {
        $length = [int]$firstLengthByte
    }
    else {
        $lengthByteCount = $firstLengthByte -band 0x7F
        if ($lengthByteCount -eq 0 -or $lengthByteCount -gt 4 -or $Offset.Value + $lengthByteCount -gt $End) {
            throw 'Invalid DER length.'
        }
        $length = 0
        for ($index = 0; $index -lt $lengthByteCount; $index++) {
            $length = ($length -shl 8) -bor $Data[$Offset.Value]
            $Offset.Value++
        }
    }

    $valueOffset = $Offset.Value
    $elementEnd = $valueOffset + $length
    if ($elementEnd -gt $End) { throw 'DER element extends past its parent.' }
    $Offset.Value = $elementEnd
    return [pscustomobject]@{ Tag = $tag; ValueOffset = $valueOffset; Length = $length; End = $elementEnd }
}

function Test-DerBytes {
    param([byte[]]$Data, [int]$Offset, [int]$Length, [byte[]]$Expected)

    if ($Length -ne $Expected.Length) { return $false }
    for ($index = 0; $index -lt $Length; $index++) {
        if ($Data[$Offset + $index] -ne $Expected[$index]) { return $false }
    }
    return $true
}

function ConvertFrom-DerDirectoryString {
    param([byte[]]$Data, [object]$Element)

    $value = New-Object byte[] $Element.Length
    [Array]::Copy($Data, $Element.ValueOffset, $value, 0, $Element.Length)
    switch ($Element.Tag) {
        0x0C { return [Text.Encoding]::UTF8.GetString($value) }
        { $_ -in @(0x12, 0x13, 0x14, 0x16, 0x1A) } { return [Text.Encoding]::ASCII.GetString($value) }
        0x1E { return [Text.Encoding]::BigEndianUnicode.GetString($value) }
        default { throw 'Unsupported X.500 directory-string encoding.' }
    }
}

function Test-ApprovedAuthenticodeSignature {
    param([object]$Signature, [string]$ExpectedSubject)

    return $null -ne $Signature -and $Signature.Status -eq 'Valid' -and
        $null -ne $Signature.SignerCertificate -and
        (Test-ApprovedSignerSubject -Expected $ExpectedSubject -Actual $Signature.SignerCertificate.Subject)
}
