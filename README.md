# BlueBird Spotter

BlueBird Spotter is a SwiftUI app that tracks AST SpaceMobile satellites using public TLE (Two-Line Element) data.

The app provides four user-facing areas:
- `TLEs`: inspect fetched orbital elements.
- `Tracking`: watch live 1 Hz position updates.
- `Globe`: visualize satellites and orbit paths in 3D.
- `Info`: read plain-language context about AST SpaceMobile and the app pipeline.

## Platform and Tooling

- iOS 26+
- Xcode 26+
- Swift 6 concurrency model
- Dependency policy: only `SatelliteKit` (SPM `2.1.1`)

## Architecture Overview

The codebase follows MVVM + Services with a feature-first folder layout.

### Folder map

- `App/`
- Purpose: app entry point and composition root wiring.
- Current key files: `BlueBird_SpotterApp.swift`, `ContentView.swift`.

- `Features/`
- Purpose: feature-specific UI and ViewModel code.
- `Features/TLE/`: TLE list view + `CelesTrakViewModel`.
- `Features/Tracking/`: tracking UI + `TrackingViewModel`.
- `Features/Globe/`: 3D globe UI and render configuration types.
  - `Views/`: SwiftUI globe composition and `UIViewRepresentable` bridge.
  - `Controllers/`: focused SceneKit coordinator extensions (camera, orbit paths, satellite lifecycle).
- `Features/InsideASTS/`: educational content UI.

- `Core/`
- Purpose: shared, side-effect-free app logic.
- `Core/Domain/Models/`: domain entities and shared state wrappers.
- `Core/Domain/Utilities/`: conversion and parsing helpers.
- `Core/Extensions/`: small shared extensions.

- `Services/`
- Purpose: all I/O and side effects.
- `Services/TLE/`: remote fetch, cache store, repository, refresh scheduling.
- `Services/Orbit/`: orbit propagation interface + implementations.
- `Services/Tracking/`: ticker abstraction and real-time ticker.
- `Services/System/`: filesystem directory helpers.

- `Resources/`
- Purpose: app assets and 3D models.
- Current key folders: `Assets.xcassets`, `Models/`.

- `Tests/`
- `Tests/Unit/`: Swift Testing unit tests.
- `Tests/UI/`: XCTest UI tests.

### Runtime flow (MVVM + Services)

1. View triggers a ViewModel intent (for example, load/refresh/start tracking).
2. ViewModel orchestrates service calls and publishes UI-safe state.
3. Services perform network/cache/system work and return domain models.
4. Views render published state and never perform direct I/O.

## Gross Offender Split Plan (Pre-Refactor)

The following files were identified as top offenders by line count and mixed responsibilities.

1. `Features/Globe/Views/GlobeSceneView.swift` (~1889 LOC)
- Current mixing: SceneKit setup, gesture handling, camera orbit math, orbit path sampling/geometry, material/template loading, selection visuals, lighting math.
- Planned split:
  - Extract camera math/orbit animation into dedicated globe camera helper.
  - Extract orbit path sampling + geometry building into focused globe orbit-path utilities.
  - Extract lighting model and scene-environment helpers to separate files.
  - Keep `GlobeSceneView` focused on bridge/update orchestration only.

2. `Features/Globe/Views/GlobeView.swift` (~514 LOC)
- Current mixing: screen layout, persisted settings wiring, formatting helpers, debug overlays, and feature-specific component definitions.
- Planned split:
  - Move state/orchestration into a dedicated `GlobeViewModel`.
  - Extract settings panel and selection overlay into `Components/` files.
  - Move formatter helpers to `Core` utility types.

3. `Features/InsideASTS/Views/InsideASTSView.swift` (~449 LOC)
- Current mixing: long-form content data, style system, expandable card behavior, and link/source modeling in one file.
- Planned split:
  - Move static educational content into a feature model/content provider.
  - Extract reusable card components and visual helpers into `Components/`.
  - Keep root view focused on composition and section state only.

## Build and Test

Open in Xcode:

```bash
open "BlueBird Spotter.xcodeproj"
```

Build (artifacts outside repo):

```bash
xcodebuild -scheme "BlueBird Spotter" build -derivedDataPath "$TMPDIR/BlueBirdSpotter-DerivedData"
```

Run unit + UI tests (artifacts outside repo):

```bash
xcodebuild -scheme "BlueBird Spotter" test -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath "$TMPDIR/BlueBirdSpotter-DerivedData"
```

## Where to Start as a Contributor

- Start with `App/ContentView.swift` to see top-level feature composition.
- Then read one feature end-to-end:
  - View in `Features/<Feature>/Views/`
  - ViewModel in `Features/<Feature>/ViewModels/`
  - Service usage in `Services/`
- For data behavior, read `Services/TLE/TLERepository.swift` first.
- For orbital math flow, read `Services/Orbit/SGP4OrbitEngine.swift` then `Core/Domain/Utilities/` converters.

## Contributor Docs

- Contribution workflow and local commands: `CONTRIBUTING.md`
- Current license status: `LICENSE`
