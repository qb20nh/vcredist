# Runtime input review checkpoint

As of **2026-10-20**, the [candidate inventory](../manifests/runtime-inputs.candidates.json)
contains **24 unique binary packages**. It records official discovery sources and
unresolved review fields. No runtime binaries were downloaded or installed to
prepare this checkpoint, and no release lockfile was created.

## Source verification

The Windows [Verify source run](https://github.com/qb20nh/vcredist/actions/runs/33117161240)
succeeded for commit `765ec5c8a4dbe50de83b170c94a13f3bf0e929fa`. Its policy tests,
Windows PowerShell checks, x86/x64/ARM64 fixture bootstrap builds, and native
self-tests passed. This establishes source and fixture behavior, not real-input
installation, standalone packaging, or redistribution rights. The new evidence
collector has not yet run on Windows.

## Candidate coverage

| Component | Candidate version | Package coverage | Evidence still needed |
| --- | --- | --- | --- |
| .NET Desktop and ASP.NET Core 8 | 8.0.32 | Six installers: two families across x86/x64/ARM64 | Actual bytes, Microsoft signature, exact binary license, OS gates and installed-runtime detection |
| .NET Desktop and ASP.NET Core 9 | 9.0.21 | Six installers across x86/x64/ARM64 | Same |
| .NET Desktop and ASP.NET Core 10 | 10.0.13 | Six installers across x86/x64/ARM64 | Same |
| VC++ v14 | File version not yet observed | Three official x86/x64/ARM64 downloads | Windows file version and signature, applicable Visual Studio redistribution grant, skip-newer detection |
| .NET Framework | 4.8 and 4.8.1 | Two offline installers with x86/x64 discovery evidence | Windows evidence, native ARM64 package coverage, OS-dependent selection, installed Release registry searches, exact EULAs |
| DirectX June 2010 | 9.29.1974.1 | One archive for x86/x64 legacy components | Windows evidence, EULA review, extraction and actual `DXSETUP.exe /silent` orchestration |

The .NET versions were released on 2026-10-13 according to Microsoft's
[8.0](https://builds.dotnet.microsoft.com/dotnet/release-metadata/8.0/releases.json),
[9.0](https://builds.dotnet.microsoft.com/dotnet/release-metadata/9.0/releases.json),
and [10.0](https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json)
release metadata. The inventory preserves each selected URL and upstream SHA-512,
plus the SHA-256 of the retrieved metadata snapshot. Upstream digests have not
been described as locally verified payload hashes.

[endoflife.date](https://endoflife.date/dotnet) was used only to choose candidate
support cycles: 8 and 9 end support on 2026-11-10; 10 ends on 2028-11-14. Refresh
this decision before a release. Microsoft is the source for all binary URLs.

VC++ links were resolved using HEAD redirects from Microsoft's
[latest-downloads page](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170).
The page intentionally omits the changing latest file version. The hexadecimal
part of a download URL is not treated as a verified file digest. Microsoft also
documents that the x64 package contains ARM64 binaries; inventory package labels
do not establish a policy for every emulated application architecture.

Framework URLs come from Microsoft's official
[4.8 Dockerfile](https://raw.githubusercontent.com/microsoft/dotnet-framework-docker/main/src/runtime/4.8/windowsservercore-ltsc2019/Dockerfile)
and [4.8.1 Dockerfile](https://raw.githubusercontent.com/microsoft/dotnet-framework-docker/main/src/runtime/4.8.1/windowsservercore-ltsc2022/Dockerfile).
Shared x86/x64 packages appear once in the inventory. Native ARM64 coverage
requires separate evidence.

## Release blockers

**Redistribution terms need an applicable grant.** Microsoft's
[VC++ deployment documentation](https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files?view=msvc-170)
limits redistribution to licensed Visual Studio users under the applicable
license and REDIST grant. The current
[runtime-use terms](https://visualstudio.microsoft.com/license-terms/vs2026-ga-visualcpp-v14-redist-runtime/)
do not themselves supply that grant: their restrictions prohibit distribution
and standalone offerings. The publisher's applicable grant and its coverage of
this runtime pack must be established before redistribution.

The modern .NET source repositories use MIT licenses, but this checkpoint has
not established the exact license and third-party notices of each Microsoft-built
installer. The generic [.NET Library terms](https://dotnet.microsoft.com/en-us/dotnet_library_license.htm)
are a reference to investigate, not an assertion that they apply to these exact
files. Review the actual installer terms. Framework and DirectX deployment
guidance likewise does not substitute for reviewing their applicable EULAs.

**Framework 4.x needs OS-aware authoring.** These versions are in-place updates.
[Compatibility](https://learn.microsoft.com/en-us/dotnet/framework/get-started/system-requirements)
differs between 4.8 and 4.8.1; for example, Server 2019 uses 4.8 while Server
2022 can install 4.8.1. Compatibility tables do not themselves establish current
OS lifecycle eligibility. The source authoring currently chains all selected
architecture inputs under a feature flag; it does not implement the required
OS-dependent choice. Installed-version registry searches and skip-newer behavior
must also be authored and tested before creating executable lockfile conditions.

**NetFx3 has a new Windows boundary.** Microsoft's
[current installer guidance](https://learn.microsoft.com/en-us/dotnet/framework/install/dotnet-35-windows-11)
and [source include](https://raw.githubusercontent.com/dotnet/docs/main/docs/framework/install/includes/dotnet-35-installer.md)
state that Windows 11 26H1, build 28000 and later, requires a standalone installer
and cannot install NetFx3 as a Windows component. The existing DISM helper covers
the component-servicing path only. The new standalone discovery link is recorded
separately in the inventory; its canonical input, license, architecture coverage,
and OS-gated integration remain unresolved. Do not manufacture a NetFx3 payload
for earlier Windows versions.

**The DirectX download is an archive.** The
[official download](https://www.microsoft.com/en-us/download/details.aspx?id=8109)
must be staged and extracted before invoking the actual setup program.
[Microsoft's setup guidance](https://learn.microsoft.com/en-us/windows/win32/dxtecharts/directx-setup-for-game-developers)
requires the necessary CABs and setup files, and addresses EULA acceptance.
Chaining the outer archive as a generic `ExePackage` does not establish runtime
installation. No native ARM64 DirectX input has been reviewed.

## Collect Windows byte evidence

Run on Windows, or use the **Collect candidate runtime evidence** workflow.
It runs on pull requests changing the inventory or collector and can also be
started manually after this source is available in GitHub Actions:

```powershell
./tests/Test-RuntimeInputEvidence.ps1
./tools/Get-RuntimeInputEvidence.ps1 -ValidateOnly
./tools/Get-RuntimeInputEvidence.ps1
```

The collector validates all candidate URLs and filenames before downloading.
It uses canonical Microsoft HTTPS URLs without redirects, checks upstream
SHA-512 when supplied, and requires valid Microsoft Authenticode signatures.
It records observed SHA-256, SHA-512, exact size, file/product version, signer
subject, certificate thumbprint and expiry in
`artifacts/runtime-input-evidence/evidence.json`. The report includes the input
inventory digest, explicit pending/failed entries, and `releaseReady: false`.
Collection completeness describes byte evidence only. It does not establish OS
compatibility, license rights, correct install behavior, or independent review.

The collector does not execute payloads. Downloads stay in a temporary directory
and are removed; the workflow uploads metadata only. A signature or hash mismatch
fails collection. `-ValidateOnly` performs no downloads and runs on Linux too.

## Independent review before a release lockfile

Review the inventory, Windows evidence, applicable redistribution grants and
notices, OS/architecture coverage, installed-version detection, arguments and
exit codes. Implement and verify the Framework, NetFx3 and DirectX orchestration
gaps above. Only then create and independently review
`manifests/runtime-inputs.lock.json`; do not rename the candidate file or fill
unknown fields with placeholders. Both real bundle modes and all supported
architectures must pass Windows verification before release publication.
