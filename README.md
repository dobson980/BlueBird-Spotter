# BlueBird Spotter

BlueBird Spotter is a SwiftUI app for exploring and tracking AST SpaceMobile satellites using public TLE (Two-Line Element) data from CelesTrak.

The repository is organized for open-source contribution with a feature-first layout, MVVM + Services boundaries, and Swift 6 concurrency patterns.

## What the App Does

- Browse current TLE data for SpaceMobile-related query groups.
- Track satellite positions at a 1 Hz cadence using SGP4 propagation.
- Visualize satellites, orbit paths, and lighting on a 3D globe.
- Explain AST SpaceMobile context and app behavior in plain language.

## Platform and Tooling

- Target platforms: iOS 26+ and macOS 26+ (SwiftUI project policy).
- Current CI/runtime validation path: iOS 26 simulator.
- Xcode 26+.
- Swift 6 (`SWIFT_VERSION = 6.0`).
- Dependency policy: `SatelliteKit` via Swift Package Manager, version `2.1.1` only.

## Quick Start

Open the project:

```bash
open "BlueBird Spotter.xcodeproj"
```

Build with artifacts outside the repository:

```bash
xcodebuild \
  -scheme "BlueBird Spotter" \
  build \
  -derivedDataPath "$TMPDIR/BlueBirdSpotter-DerivedData"
```

Run all tests (unit + UI) with artifacts outside the repository:

```bash
xcodebuild \
  -scheme "BlueBird Spotter" \
  test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath "$TMPDIR/BlueBirdSpotter-DerivedData"
```

Run unit tests only (faster CI-style command):

```bash
xcodebuild \
  -scheme "BlueBird Spotter UnitTests" \
  test \
  -only-testing:"BlueBird SpotterTests" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath "$TMPDIR/BlueBirdSpotter-DerivedData"
```

Optional result bundle for debugging failures:

```bash
xcodebuild \
  -scheme "BlueBird Spotter" \
  test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath "$TMPDIR/BlueBirdSpotter-DerivedData" \
  -resultBundlePath "$TMPDIR/BlueBirdSpotter-TestResults.xcresult"
```

## Architecture

BlueBird Spotter follows MVVM + Services.

- Views are presentation-focused (layout/composition/bindings).
- ViewModels own UI state, async orchestration, and cancellation behavior.
- Services own I/O and side effects (network, cache, system/background tasks).
- Core contains shared domain models and mostly pure utilities.

Swift 6 concurrency is used throughout:

- UI-facing state is main-actor isolated.
- Services and pure utility layers use actor-safe boundaries and `async/await`.
- Tests validate view model behavior, core math/parsing logic, and service policies.

## Repository Layout

- `App/`: app entry points and composition root.
- `Features/`: feature code grouped by domain.
- `Features/TLE`: TLE list, refresh flow, and metadata presentation.
- `Features/Tracking`: 1 Hz tracking loop and tracked satellite list UI.
- `Features/Globe`: SceneKit-backed globe rendering, camera control, orbit paths, and overlays.
- `Features/InsideASTS`: educational/context screens.
- `Core/`: shared models, extensions, and domain utilities.
- `Services/`: top-level side-effect layer (`TLE`, `Orbit`, `Tracking`, `System`).
- `Resources/`: asset catalogs, icon assets, and model resources.
- `Tests/Unit`: Swift Testing unit tests (`import Testing`).
- `Tests/UI`: XCTest UI tests (`import XCTest`).

## Where New Contributors Should Start

- `App/BlueBird_SpotterApp.swift`: app lifecycle and background refresh scheduling.
- `App/ContentView.swift`: tab composition and feature wiring.
- `App/AppCompositionRoot.swift`: dependency composition root.
- `Services/TLE/TLERepository.swift`: cache/network orchestration boundary.
- `Features/TLE/ViewModels/CelesTrakViewModel.swift`: TLE feature state machine.
- `Features/Tracking/ViewModels/TrackingViewModel.swift`: live tracking loop and update pipeline.
- `Features/Globe/ViewModels/GlobeViewModel.swift`: globe-level UI orchestration.

## Data Source and Accuracy Notes

- TLE data is fetched from CelesTrak endpoints.
- TLE-based propagation is an approximation and can drift from exact real-world state.
- This project is for educational and informational use.

## Contributing

- Read `CONTRIBUTING.md` for setup, testing, and PR expectations.
- Read `AGENTS.md` for repository architecture and coding rules.

## License

See `LICENSE`.
