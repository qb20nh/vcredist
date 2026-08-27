# Supply-chain policy

## Input policy

Inputs must originate from Microsoft, be unmodified, carry a valid expected
Microsoft Authenticode signature, and match a reviewed SHA-256 digest. A current
endoflife.date record may identify a supported .NET cycle, but it never serves
as a binary source or integrity authority.

## Release policy

All external GitHub actions are full-commit pinned. Releases may be created only
after repository tests, manifest validation, deterministic packaging, SBOM
generation, and provenance attestation. GitHub immutable releases must be
enabled before publishing. Correct mistakes with a new version; never replace a
tag or release asset.

## Installer policy

No feature is installed without an explicit bundle feature selection. Download,
hash, or signature failure is fatal. The installer never uninstalls or hides an
existing runtime. .NET Framework 4.x is selected as an OS-compatible in-place
update; it is never treated as side-by-side.

The optional .NET Framework 3.5 feature uses an open-source native helper that
launches only the target machine's `System32\\dism.exe` with fixed arguments.
It accepts no source path, never downloads Windows media, and propagates the
Windows servicing result to the bundle. If Windows cannot obtain matching
feature files from a local, configured, or Windows Update source, installation
fails without substituting an unreviewed payload.
