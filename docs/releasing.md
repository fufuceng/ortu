# Release process

Official releases are intended for GitHub Releases and a Homebrew tap. Do not publish the ad-hoc signed output from `scripts/package-local.sh` as an official binary.

## Prerequisites

- Repository administration access for `fufuceng/ortu`.
- A final bundle identifier owned by the maintainer.
- An Apple Developer ID Application certificate.
- App-specific notarization credentials stored as GitHub Actions secrets.
- A Homebrew tap repository and its update credentials.

## Required release gate

1. Update `CHANGELOG.md` and application version metadata.
2. Run `make check` from a clean checkout.
3. Complete the manual matrix in `docs/testing.md`.
4. Build a universal `arm64` and `x86_64` application where both architectures remain supported.
5. Sign with hardened runtime and the Developer ID certificate.
6. Submit to Apple's notary service, wait for success, and staple the ticket.
7. Verify the signature, Gatekeeper assessment, bundle metadata, and launch behavior on a clean Mac.
8. Produce a DMG, SHA-256 checksum, SBOM, and provenance attestation.
9. Publish the immutable GitHub release, then update the Homebrew cask checksum.

## Failure and rollback

Never replace assets under an existing version tag. If a release is broken, mark it clearly, restore the Homebrew cask to the last known-good version when necessary, and publish a new patch version. Keep signing and notarization logs as private build records without exposing secrets.

The automated signing/notarization workflow should be added only after ownership of the `dev.ortu.app` bundle identifier, Apple Team ID, and secret names are confirmed. This avoids checking in a release pipeline whose identity or trust assumptions are placeholders.
