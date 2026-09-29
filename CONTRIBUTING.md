# Contributing to Örtü

Thank you for helping improve Örtü. The project favors small, reviewable changes that preserve its native, offline, energy-conscious design.

## Before you start

- Use macOS 13 or newer and a Swift 6.1-compatible Xcode toolchain.
- Search existing issues before opening a duplicate.
- Discuss large UI, architecture, package-format, or dependency changes in an issue first.
- Security vulnerabilities must follow `SECURITY.md`, not a public issue.

## Local workflow

```sh
make format-check
make test
make package
make check
```

`make check` is the authoritative local quality gate. It lints changed Swift files, compiles warnings as errors, runs tests with coverage, verifies the coverage floor, packages and checks the app signature, and validates every built-in `.ortupack` with the release binary.

Format intentional Swift edits with:

```sh
make format
```

## Pull requests

Keep one concern per pull request. Include tests for changed behavior and complete the pull request template. UI and display changes should include screenshots and the macOS/display configuration used for manual verification.

Use clear commit subjects; Conventional Commit prefixes such as `feat:`, `fix:`, `test:`, `docs:`, and `build:` are encouraged but not required.

New dependencies require a rationale covering binary size, maintenance, license, security, privacy, and idle-energy impact. Runtime network dependencies are outside the current product scope.

## Cover artwork

Only submit artwork you created or have the right to redistribute. Include attribution and an allowed SPDX license in the pack manifest. See `docs/ortupack-v1.md` for the format and validation rules.

## Definition of done

- The behavior is documented where users or contributors need it.
- Automated tests cover the important success and failure paths.
- `make check` passes.
- Accessibility, privacy, security, and energy effects have been considered.
- Generated `.build/` and `dist/` artifacts are not committed.
