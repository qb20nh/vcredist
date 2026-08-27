# Runtime Pack Verified

Runtime Pack Verified builds auditable WiX Burn installer bundles (`.exe`) for
common Microsoft application prerequisites. It is an independent redesign of
the upstream AIO project: it never modifies Microsoft installers, hides
installed components, or removes existing runtimes.

Each release provides two installer modes for x86, x64, and ARM64:

- **Bootstrap bundle** downloads only reviewed Microsoft inputs during installation.
- **Standalone bundle** embeds those same unmodified inputs for offline use.

Both modes expose the same selectable features: VC++ v14, supported .NET
Desktop and ASP.NET Core runtimes, OS-compatible .NET Framework, and legacy
DirectX June 2010 side-by-side libraries. ARM32 is deliberately unsupported.

When selected, .NET Framework 3.5 is fully automated through Windows servicing:
the bundle invokes the operating system's own DISM capability path, which uses
local component files, an enterprise-configured repair source, or Windows
Update. It does not embed a mismatched Windows media payload or prompt users
for a source path.

## What is verified

Every runtime input is recorded in an immutable, reviewed manifest with its
official URL, version, SHA-256 digest, expected Microsoft Authenticode subject,
and license/source record. The bootstrap installer downloads and verifies that
input before executing it; the standalone builder verifies it before embedding
it. A mismatch fails closed.

Release artifacts include a component manifest, SPDX SBOM, SHA-256 checksums,
GitHub build provenance attestations, and immutable GitHub release protection.
See [docs/VERIFYING.md](docs/VERIFYING.md).

## Important boundaries

The project code and build logic are open source. Microsoft redistributables
inside a standalone bundle are proprietary, unmodified third-party inputs; their
presence does not make them open source. The repository contains neither those
inputs nor modified copies of them.

The DirectX feature installs Microsoft’s June 2010 *side-by-side* legacy SDK
libraries (including D3DX9 where needed). It does not replace Windows DirectX
and it is not uninstallable.

## Maintainer flow

1. Generate candidate input records from official Microsoft download pages.
2. Independently review the URL, license, SHA-256, signature, feature, and
   architecture selection.
3. Commit the manifest and create an annotated signed version tag.
4. CI builds all bundle variants from locked source/toolchain inputs, emits SBOMs,
   checksums and attestations, then publishes an immutable release.

No release is published merely to demonstrate this pipeline.
