# Architecture

## Decision summary

Örtü is a native modular monolith. AppKit owns application, menu bar, window, display, and pointer-event integration. SwiftUI is limited to Settings. There is no backend, database, network client, executable plugin runtime, or cross-process protocol.

```text
AppDelegate ──> AppModel ──> OverlayCoordinating ──> one overlay window / display
                   │                  └── OverlayView ──> OverlayInteractionState
                   ├── CoverPackStore actor ──> archive inspector ──> validator
                   └── injected preferences / login / workspace boundaries
```

## Module boundaries

- `OrtuApp` owns process lifecycle and menu-bar commands.
- `AppModel` owns user-visible state and coordinates injected application-service boundaries.
- `OverlayCoordinator` owns display selection and overlay-window lifecycle.
- `OverlayView` owns AppKit rendering and short-lived animation scheduling. `OverlayInteractionState`, `ClothMesh`, and `OverlayLayout` contain deterministic, directly tested calculations.
- `CoverPackArchive` treats external ZIP bytes as untrusted input.
- `CoverPackValidator` validates the expanded data-only format.
- The `CoverPackStore` actor owns staging, installation, semantic-version updates, and removal away from the main actor.

## Key invariants

- Idle work is event-driven: no polling, recurring timer, or permanent render loop.
- One logical drape state controls all active overlay windows.
- A pack becomes visible only after archive inspection and expanded-content validation succeed.
- Installed pack identifiers are unique. Built-in identifiers are reserved.
- Preferences contain no secrets and remain local.

## Data and consistency

`UserDefaults` stores small appearance preferences behind an injected boundary. Pack installation uses a private staging directory followed by filesystem replacement and is serialized by an actor. The app expects at-most-one local command execution; distributed transactions, events, outbox, CDC, and exactly-once delivery do not apply.

## Adding a dependency or subsystem

Use an architecture decision record under `docs/decisions/` when a change introduces a runtime dependency, network access, executable extensions, persistent storage beyond preferences, a background worker, or a continuous render mechanism. State the user value, rejected alternatives, energy and security cost, migration, and rollback.
