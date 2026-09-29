# AGENTS.md

This file is the operating contract for coding agents and automated contributors working on Örtü.

## Mission

Örtü is a native, offline macOS menu bar application. Preserve these product invariants:

- No network access, telemetry, account system, or background polling.
- Near-zero idle CPU/GPU work; animation exists only during direct interaction or a short transition.
- External `.ortupack` files are data-only and never execute code.
- No Accessibility, Screen Recording, or Input Monitoring permission requirements.
- macOS 13 is the minimum deployment target.

## Repository map

- `Sources/Ortu/`: application source and bundled cover packs.
- `sources/`: read-only project-reference mirror; never edit or ship it.
- `Tests/OrtuTests/`: Swift Testing suites.
- `scripts/`: local quality, packaging, and pack-authoring tools.
- `Packaging/`: application bundle metadata.
- `docs/`: architecture, testing, and `.ortupack` specifications.
- `dist/` and `.build/`: generated output; never edit or commit them.

## Required workflow

1. Read `README.md`, `CONTRIBUTING.md`, and the relevant file in `docs/`.
2. Keep changes narrowly scoped. Do not mix formatting-only edits with behavioral changes.
3. Add or update tests for every behavioral change and bug fix.
4. Run `make check` before handing off. A change is incomplete while this command fails.
5. Report any checks that could not run and why; never imply unrun checks passed.

Use `make format` only for an intentional formatting pass. Generated app bundles and coverage data are not source artifacts.

## Engineering rules

- Prefer the existing native modular monolith. Do not introduce services, IPC, a web view, or a plugin runtime without an accepted architecture decision record.
- Keep AppKit lifecycle/window behavior at the edges and deterministic calculations in testable value types.
- Keep UI work on `@MainActor`. Move expensive file or image work away from interactive paths when it becomes measurable.
- Inject filesystem or preference dependencies when new logic needs isolation in tests.
- Model expected failures with typed errors and actionable localized messages.
- Avoid force unwraps, force casts, force tries, detached tasks, and unbounded caches.
- Do not add a timer, display link, file watcher, or network client without documenting its idle-energy impact.
- Validate untrusted files before decoding or activation. Preserve archive size, path, symlink, file-count, image-dimension, and checksum limits.
- Use semantic versions for `.ortupack` updates. Never silently downgrade or replace a built-in pack.
- Do not add a third-party dependency when the platform SDK provides a small, maintainable solution. Explain the lifecycle and security cost when one is necessary.

## Test expectations

- Pure algorithms: focused unit tests including boundaries.
- Package/archive changes: valid input, malformed input, traversal/symlink/size edge, and atomicity tests.
- Window or multi-display changes: unit-test geometry/state and document the manual hardware scenario.
- Animation changes: test state/progress calculations and confirm Reduce Motion behavior.
- Performance-sensitive changes: include before/after idle CPU, memory, or redraw evidence when relevant.

The coverage floor prevents regression; it is not a quality target. Prefer risk-based tests over chasing a percentage.

## Pull request handoff

Include:

- User-visible outcome.
- Design and trade-offs.
- Tests and manual verification performed.
- Energy, privacy, security, or accessibility impact.
- Follow-up work deliberately left out.
