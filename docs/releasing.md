# Release process

Örtü publishes the same immutable, universal DMG through GitHub Releases and the `fufuceng/homebrew-tap` Homebrew cask. Until a Developer ID is available, release apps are ad-hoc signed and not notarized. Users must explicitly approve the first launch in macOS Privacy & Security.

## Current trust model

- GitHub Actions builds every release from a `vX.Y.Z` tag whose commit is contained in `main`.
- The application is ad-hoc signed to preserve bundle integrity, not to establish an Apple-verified developer identity.
- Every release includes the DMG, a SHA-256 checksum, and the exact generated Homebrew cask.
- Homebrew verifies the immutable DMG checksum but cannot replace Apple notarization.
- The cask preserves quarantine and explains Apple’s **Open Anyway** flow. It must not silently remove quarantine attributes.

Users should install only from `github.com/fufuceng/ortu` or `fufuceng/homebrew-tap` and compare checksums when their risk profile requires it.

## Automated tag release

1. Update `CHANGELOG.md` and any user-facing version notes.
2. Run `make check` from a clean checkout.
3. Complete the manual matrix in `docs/testing.md`.
4. Create and push an annotated semantic-version tag such as `v0.1.0` from a commit on `main`.
5. `.github/workflows/release.yml` reruns the quality gate.
6. `scripts/package-release.sh` builds a universal `arm64` and `x86_64` application, ad-hoc signs it, creates a DMG, and writes its SHA-256 checksum.
7. `scripts/render-homebrew-cask.sh` renders the cask from the release version and checksum.
8. The workflow publishes an immutable GitHub release.
9. When `HOMEBREW_TAP_DEPLOY_KEY` is configured, the workflow updates `fufuceng/homebrew-tap` after the release exists.

For a local release-package dry run:

```sh
make release-package VERSION=0.1.0
./scripts/render-homebrew-cask.sh 0.1.0 dist/Ortu-0.1.0.dmg dist/ortu.rb
```

## Homebrew tap authentication

Use a dedicated SSH deploy key with write access to `fufuceng/homebrew-tap`; do not reuse a personal access token with broad account permissions.

1. Add the public key to the tap repository as a write-enabled deploy key.
2. Add the private key to the `ortu` repository’s `release` environment as `HOMEBREW_TAP_DEPLOY_KEY`.
3. Require maintainer approval on the `release` environment if desired.

The DMG release still succeeds when this secret is absent. In that case, `ortu.rb` is attached to the GitHub release and the tap must be updated manually.

## Required release verification

- `make check`
- `lipo -archs Ortu.app/Contents/MacOS/Ortu` contains `arm64` and `x86_64`
- `codesign --verify --deep --strict Ortu.app`
- `hdiutil verify Ortu-<version>.dmg`
- DMG installation and first-launch warning on a clean Mac
- **Open Anyway** flow from System Settings → Privacy & Security
- `brew install --cask fufuceng/tap/ortu`
- `brew upgrade --cask ortu`
- `brew uninstall --cask ortu`

## Failure and rollback

Never replace assets under an existing version tag. If a release is broken, mark it clearly, restore the Homebrew cask to the last known-good version when necessary, and publish a new patch version. A checksum change without a version change is treated as a compromised or incorrectly mutated release.

## Future Developer ID migration

When a Developer ID becomes available, keep the release URLs and cask unchanged. Replace ad-hoc signing with hardened-runtime Developer ID signing, submit the app to Apple’s notary service, staple the ticket, add Gatekeeper verification, and remove the unsigned-build caveat. The Homebrew and GitHub installation commands do not need to change.
