# BlueBird Spotter

BlueBird Spotter is a SwiftUI app for viewing and tracking AST SpaceMobile satellites using public TLE (Two-Line Element) data.

The app is designed to be readable and contributor-friendly, with a feature-first structure and clear MVVM + Services boundaries.

## What the App Does

- `TLEs`: fetch and inspect current orbital elements.
- `Tracking`: follow live position updates at a 1 Hz cadence.
- `Globe`: render tracked satellites and orbit paths on a 3D globe.
- `Info`: explain AST SpaceMobile context and app behavior in plain language.

## Platform Requirements

- iOS 26+
- Xcode 26+
- Swift 6
- Dependency policy: `SatelliteKit` via Swift Package Manager (`2.1.1`)

## Quick Start

Open in Xcode:

```bash
open "BlueBird Spotter.xcodeproj"
```

Build (artifacts outside repo):

```bash
xcodebuild -scheme "BlueBird Spotter" build -derivedDataPath "$TMPDIR/BlueBirdSpotter-DerivedData"
```

Run tests (artifacts outside repo):

```bash
xcodebuild -scheme "BlueBird Spotter" test -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath "$TMPDIR/BlueBirdSpotter-DerivedData"
```

## Project Structure

The repository is organized by feature and responsibility:

- `App/`
- Purpose: app entry points and composition root.

- `Features/`
- Purpose: feature-specific views, view models, models, and UI components.
- Current features: `TLE`, `Tracking`, `Globe`, `InsideASTS`.

- `Core/`
- Purpose: shared domain models, pure utilities, and extensions.

- `Services/`
- Purpose: network/cache/system/background integrations and other side effects.
- Domains: `TLE`, `Orbit`, `Tracking`, `System`.
- Rule: services do not import SwiftUI.

- `Resources/`
- Purpose: assets and 3D resources.

- `Tests/`
- `Tests/Unit/`: Swift Testing unit tests.
- `Tests/UI/`: XCTest UI tests.

## Architecture Overview

BlueBird Spotter uses MVVM + Services:

1. Views handle layout, user interaction, and state presentation.
2. ViewModels own UI state and orchestrate work.
3. Services perform I/O, caching, and background/system integration.
4. Core utilities and models hold shared, mostly side-effect-free logic.

This keeps business logic testable and keeps rendering code separate from network and persistence concerns.

## Data Notes

- Orbit visualization and positions are based on public TLE data.
- TLE-based tracking is an approximation and can drift from exact real-world positions.
- This project is for educational and informational use.

## Contributing

Please read:

- `CONTRIBUTING.md` for setup, test commands, and PR expectations.

## License

See `LICENSE`.
