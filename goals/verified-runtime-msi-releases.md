# Goal: Verifiable Microsoft Runtime Bundle Releases

Slug: `verified-runtime-burn-releases`
Status: Draft
Activation: `/goal @goals/verified-runtime-msi-releases.md`

This file is not an active Goal. It becomes active thread-scoped Goal state only after the activation command is run.

## Goal Text

Build a fully auditable, open-source WiX Burn release system for `qb20nh/vcredist`, verified by reproducible build inputs, repository tests, architecture-aware installer bundles, SHA-256 checksums, SBOMs, GitHub provenance attestations, and immutable GitHub releases. Publish both bootstrap and standalone bundles for x86, x64, and ARM64. The selectable components must include the supported Microsoft Visual C++ v14 redistributable, .NET Desktop Runtime and ASP.NET Core Runtime for every currently supported .NET cycle, the newest compatible .NET Framework 4.x plus separately handled .NET Framework 3.5, and the legacy DirectX June 2010 side-by-side runtime. Preserve unmodified Microsoft inputs, never silently uninstall or hide existing components, and refuse any input that fails its reviewed SHA-256 or Authenticode signer check. Use Microsoft sources for binaries and endoflife.date only to determine candidate .NET support cycles. Between iterations, use the smallest evidence-backed change, run relevant local tests, and record a checkpoint. If licensing, a supported architecture, a reproducible build input, or an attestation/immutable-release capability blocks the work, stop with the failing evidence, attempted paths, and the exact decision or source needed.

## Interview Summary

- Desired outcome: Public source and two verifiable WiX Burn release variants: bootstrap (download-and-verify) and standalone (offline inputs embedded).
- Components: VC++ v14; .NET Desktop and ASP.NET Core runtimes for supported cycles; newest compatible .NET Framework 4.x; separate .NET Framework 3.5; legacy DirectX June 2010 side-by-side runtime.
- Architectures: x86, x64, and ARM64. ARM32 is excluded because no matching currently supported Microsoft modern-.NET/VC++ input set was established.
- Evidence: Tests validate manifests, selection and architecture rules, deterministic packaging, SBOM, GitHub attestation, and immutable release status. Release assets are independently verified with GitHub CLI.
- Constraints: No modified Microsoft installers, unreviewed mirrors, silent uninstall/hiding/registry override, or hash/signature bypass.
- Scope: The `qb20nh/vcredist` fork, official Microsoft download/licensing docs, endoflife.date support data, WiX/toolchain documentation, GitHub Actions, and release APIs. Network access and GitHub writes are allowed for this project.
- Autonomy: Iterate through low-risk source/build changes and tests; stop before an unlicensed redistribution, unsupported architecture claim, or irreversible release publication lacking the stated verification evidence.
- Budget: Continue until acceptance evidence is complete or no defensible path remains; do not publish a production release merely to demonstrate CI.
- Reporting: Concise checkpoints with commands/evidence, then a final artifact summary, verification status, and any manual GitHub protections still needed.

## Assumptions

- WiX Burn bundles are the top-level artifacts because their purpose is to safely orchestrate multiple vendor installers; their bootstrap and standalone variants share source and policy.
- Standalone releases may contain unmodified proprietary Microsoft redistributable inputs, but project code, build instructions, manifests, and provenance are fully open and auditable.
- The latest supported .NET Framework 4.x is selected by OS compatibility rather than attempting to install mutually exclusive 4.x versions together.
- DirectX means the Microsoft DirectX End-User Runtimes (June 2010) package for legacy side-by-side libraries, not replacement of the OS DirectX runtime.

## Non-goals

- ARM32, unsupported .NET cycles, modified MSIs, legacy third-party runtime packs, or runtime removal/repair/hiding behavior.
- Claiming Microsoft proprietary binaries themselves are open source.
- Publishing an unverified release or bypassing immutable-release controls.

## Verification Checklist

- [ ] All build and release inputs have a reviewed version, official source URL, SHA-256 digest, signer expectation, and licensing record.
- [ ] Bootstrap and standalone WiX Burn bundle artifacts build for x86, x64, and ARM64 from a locked toolchain and expose the agreed selectable feature set.
- [ ] Architecture, OS, and .NET Framework in-place-update rules are tested.
- [ ] Bootstrap download failure, hash mismatch, and signer mismatch fail closed.
- [ ] Standalone payload hashes match the reviewed input manifest.
- [ ] The repository excludes modified MSIs, SFX stubs, and opaque non-Microsoft build payloads.
- [ ] Release artifacts have deterministic-build evidence, SHA-256 checksums, SBOMs, full build provenance attestations, and consumer verification commands.
- [ ] GitHub immutable-release status is asserted before publication.
- [ ] Local and CI verification pass without warning suppression.

## Notes

- .NET support cycles are observed from `https://endoflife.date/dotnet` and `https://endoflife.date/dotnetfx`; those sources do not authorize or host installer binaries.
- The current Microsoft VC++ v14 documentation is the authority for mainstream runtime inputs.
