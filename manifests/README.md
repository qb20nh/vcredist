## Verified runtime inputs

`runtime-inputs.lock.json` is deliberately **not** committed until every entry has
been independently reviewed.  It is a release gate, not a discovery list.  Every
input must state its canonical Microsoft URL, SHA-256, SHA-512 (for Burn remote
payload validation), exact file size, Authenticode subject, install arguments,
detection condition, and licensing page.

Use `runtime-inputs.example.json` only to exercise tooling. It is intentionally
invalid as a release input and is rejected by release scripts.

The standalone build obtains a local copy using `tools/Resolve-VerifiedInputs.ps1`.
That script validates the Microsoft signature, size, SHA-256, and SHA-512 before
the file can be passed to WiX. The bootstrap build carries Burn remote-payload
metadata, so the engine checks the SHA-512 and size of each downloaded file before
execution.

Do not commit Microsoft or third-party runtime binaries to this repository.

## Candidate inventory

`runtime-inputs.candidates.json` records discovery evidence as of 2026-10-20. It is
not a release lockfile: upstream hashes are distinguished from locally verified
bytes, licensing and detection fields remain unresolved, and the release parser
rejects this document. One candidate represents one binary, which may support
multiple architectures; it is not a bundle-selection decision.

See [the input review checkpoint](../docs/RUNTIME-INPUT-REVIEW.md) for sources,
compatibility and redistribution blockers, and the Windows evidence workflow.
Validate the inventory without downloading anything:

```powershell
./tools/Get-RuntimeInputEvidence.ps1 -ValidateOnly
```
