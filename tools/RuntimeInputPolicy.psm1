Set-StrictMode -Version Latest

# Keep this list in one place: both downloaded inputs and Burn download URLs must
# be restricted to the same canonical Microsoft endpoints.
$script:ApprovedRuntimeInputHosts = @(
    'download.microsoft.com',
    'download.windowsupdate.com',
    'download.visualstudio.microsoft.com',
    'dotnetcli.blob.core.windows.net',
    'builds.dotnet.microsoft.com'
)

function Assert-ApprovedRuntimeInputUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$SourceUrl,

        [Parameter(Mandatory)]
        [string]$InputId
    )

    $uri = $null
    if (-not [Uri]::TryCreate($SourceUrl, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne [Uri]::UriSchemeHttps -or
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        $script:ApprovedRuntimeInputHosts -notcontains $uri.Host.ToLowerInvariant()) {
        throw "Input '$InputId' does not use an approved canonical Microsoft HTTPS URL without embedded credentials."
    }

    return $uri
}

Export-ModuleMember -Function Assert-ApprovedRuntimeInputUrl
