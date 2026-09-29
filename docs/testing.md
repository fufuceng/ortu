# Testing and quality gates

## Local commands

| Command | Purpose |
|---|---|
| `make format` | Apply the repository's `swift-format` rules. |
| `make format-check` | Check formatting without modifying files. |
| `make test` | Run Swift Testing suites. |
| `make coverage` | Run tests with coverage and enforce the floor. |
| `make package` | Build and ad-hoc sign `dist/Ortu.app`. |
| `make check` | Run the same complete gate used by CI. |

## CI policy

Pull requests must pass:

1. Strict `swift-format` lint for every changed Swift file. The full repository can be audited with `ORTU_FORMAT_ALL=1 make format-check`.
2. Compilation with warnings treated as errors.
3. All Swift tests with code coverage.
4. A 55% total line-coverage regression floor.
5. Release app packaging, plist validation, and signature verification.
6. Validation of every bundled cover pack with the packaged release binary.
7. Dependency review and Swift CodeQL analysis.
8. A separate build and test run on GitHub's `macos-15-intel` runner while Intel remains supported.

Total line coverage is currently above 60%. CI uses a conservative 55% floor so toolchain-level differences do not create noise while genuine regressions still fail. Risk-heavy package parsing remains above 80%, and AppKit surfaces have hosted construction smoke tests in addition to deterministic state tests.

## Manual release matrix

Before a tagged release, verify:

- Apple Silicon and Intel where supported.
- One display, mixed-scale dual displays, and display hot-plug.
- Spaces, full-screen apps, Stage Manager, sleep/wake, and login launch.
- Reduce Motion, Reduce Transparency, VoiceOver, and keyboard-only operation.
- Idle CPU, memory, wakeups, and network bytes for at least ten minutes.
- `.ortupack` install, duplicate, upgrade, downgrade rejection, removal, drag/drop, and Finder open.

Record OS version, hardware, display arrangement, and results in the release pull request.
