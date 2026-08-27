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
