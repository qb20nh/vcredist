# Verifying a release

For every downloaded bundle, verify all three layers:

```powershell
Get-FileHash .\RuntimePack-vX.Y.Z-x64-Standalone.exe -Algorithm SHA256
gh attestation verify .\RuntimePack-vX.Y.Z-x64-Standalone.exe -R qb20nh/vcredist
```

The local hash must equal the matching entry in `SHA256SUMS.txt`. GitHub
attestation verification identifies the source repository, commit, workflow,
and built artifact. GitHub immutable releases prevent assets on a published
release from being replaced. Inspect `sbom.spdx.json`, `release-metadata.json`,
and the committed input lockfile before installation.

For the standalone bundle, the release job stages every Microsoft input through
the signature, size, SHA-256, and SHA-512 checks before WiX embeds it. For the
bootstrap bundle, Burn verifies the locked SHA-512 and size after download. A
matching digest identifies the same already signer-verified bytes; neither mode
uses a mirror or an unpinned redirect.
