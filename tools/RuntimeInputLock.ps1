Set-StrictMode -Version Latest

$script:ApprovedSignerSubject = 'Microsoft Corporation'
$script:ApprovedSourceHosts = @(
    'download.microsoft.com',
    'download.windowsupdate.com',
    'download.visualstudio.microsoft.com',
    'dotnetcli.blob.core.windows.net',
    'builds.dotnet.microsoft.com'
)

function Assert-LockProperty {
    param([object]$Object, [string]$Name, [string]$Context)

    if ($null -eq $Object.PSObject.Properties[$Name]) {
        throw "$Context is missing required property '$Name'."
    }
}

function Assert-HttpsUri {
    param([string]$Value, [string]$Field, [string]$Context, [switch]$RequireApprovedHost)

    $uri = $null
    if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -cne 'https') {
        throw "$Context has an invalid '$Field'; an absolute HTTPS URL is required."
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
    if (@($rootNames | Where-Object { $_ -notin @('schemaVersion', 'supportedDotnetCycles', 'inputs') }).Count) {
        throw "Lockfile '$Path' contains unsupported properties."
    }
    if (-not (Test-JsonInteger $lock.schemaVersion) -or $lock.schemaVersion -ne 1) { throw "'$Path' is not a version 1 lockfile." }
    if ($lock.supportedDotnetCycles -isnot [array]) { throw "'$Path' has invalid supportedDotnetCycles." }
    $cycles = @($lock.supportedDotnetCycles)
    if (@($cycles | Where-Object { $_ -isnot [string] -or $_ -notin @('8', '9', '10') }).Count -or
        @($cycles | Sort-Object -Unique).Count -ne $cycles.Count) { throw "'$Path' has invalid supportedDotnetCycles." }
    if ($lock.inputs -isnot [array]) { throw "'$Path' has an invalid inputs collection." }
    $inputs = @($lock.inputs)
    if ($inputs.Count -eq 0) { throw "'$Path' has no runtime inputs." }

    $required = @('id', 'feature', 'architecture', 'fileName', 'sourceUrl', 'sha256', 'sha512', 'size', 'version', 'signerSubjectContains', 'installArguments', 'detectCondition', 'licenseUrl')
    $allowed = $required + @('cycle', 'inPlaceRank')
    $features = @('vc-redist-v14', 'dotnet-desktop', 'dotnet-aspnet', 'dotnet-framework', 'dotnet-framework-35', 'directx-legacy')
    foreach ($input in $inputs) {
        $context = "Runtime input '$($input.id)'"
        foreach ($name in $required) { Assert-LockProperty $input $name $context }
        if (@($input.PSObject.Properties.Name | Where-Object { $_ -notin $allowed }).Count) { throw "$context contains unsupported properties." }
        if ($input.id -isnot [string] -or $input.id -cnotmatch '^[a-z0-9][a-z0-9-]*$' -or $input.id -like 'example-*') { throw "$context has an invalid id." }
        if ($input.feature -isnot [string] -or $input.feature -notin $features) { throw "$context has an invalid feature." }
        if ($input.architecture -isnot [string] -or $input.architecture -notin @('x86', 'x64', 'arm64')) { throw "$context has an invalid architecture." }
        if ($input.fileName -isnot [string] -or $input.fileName -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "$context has an unsafe fileName." }
        if ($input.sourceUrl -isnot [string]) { throw "$context has an invalid sourceUrl." }
        if ($input.licenseUrl -isnot [string]) { throw "$context has an invalid licenseUrl." }
        Assert-HttpsUri $input.sourceUrl 'sourceUrl' $context -RequireApprovedHost
        Assert-HttpsUri $input.licenseUrl 'licenseUrl' $context
        if ($input.sha256 -isnot [string] -or $input.sha256 -cnotmatch '^[A-Fa-f0-9]{64}$') { throw "$context has an invalid SHA-256 hash." }
        if ($input.sha512 -isnot [string] -or $input.sha512 -cnotmatch '^[A-Fa-f0-9]{128}$') { throw "$context has an invalid SHA-512 hash." }
        if (-not (Test-JsonInteger $input.size) -or $input.size -lt 1) { throw "$context has an invalid size." }
        if ($input.version -isnot [string] -or $input.version -cnotmatch '^[0-9]+(\.[0-9]+){1,3}$') { throw "$context has an invalid version." }
        if ($input.signerSubjectContains -isnot [string] -or $input.signerSubjectContains -cne $script:ApprovedSignerSubject) { throw "$context has an unapproved signerSubjectContains value." }
        if ($input.installArguments -isnot [string]) { throw "$context has invalid installArguments." }
        if ($input.detectCondition -isnot [string] -or [string]::IsNullOrEmpty($input.detectCondition)) { throw "$context has an invalid detectCondition." }
        if ($input.feature -in @('dotnet-desktop', 'dotnet-aspnet')) {
            Assert-LockProperty $input 'cycle' $context
        }
        if ($null -ne $input.PSObject.Properties['cycle'] -and ($input.cycle -isnot [string] -or $input.cycle -notin @('8', '9', '10'))) { throw "$context has an invalid cycle." }
        if ($input.feature -eq 'dotnet-framework') { Assert-LockProperty $input 'inPlaceRank' $context }
        if ($null -ne $input.PSObject.Properties['inPlaceRank'] -and (-not (Test-JsonInteger $input.inPlaceRank) -or $input.inPlaceRank -lt 1)) { throw "$context has an invalid inPlaceRank." }
    }
    return $lock
}

function Test-ApprovedSignerSubject {
    param([string]$Expected, [string]$Actual)

    return $Expected -ceq $script:ApprovedSignerSubject -and
        -not [string]::IsNullOrEmpty($Actual) -and
        $Actual.Contains($Expected, [StringComparison]::OrdinalIgnoreCase)
}

function Test-ApprovedAuthenticodeSignature {
    param([object]$Signature, [string]$ExpectedSubject)

    return $null -ne $Signature -and $Signature.Status -eq 'Valid' -and
        $null -ne $Signature.SignerCertificate -and
        (Test-ApprovedSignerSubject -Expected $ExpectedSubject -Actual $Signature.SignerCertificate.Subject)
}
