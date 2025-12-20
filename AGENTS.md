# Repository Guidelines

## Project Structure & Module Organization
- `BlueBird Spotter/` holds the SwiftUI app source. Key folders: `App/` (entry point), `Views/`, `ViewModel/`, `Model/`, `Services/`, `Utilities/`.
- Assets live in `BlueBird Spotter/Assets/Assets.xcassets`.
- Tests are split into `BlueBird SpotterTests/` (unit) and `BlueBird SpotterUITests/` (UI).
- Xcode project metadata is in `BlueBird Spotter.xcodeproj`.

## Build, Test, and Development Commands
- Open in Xcode: `open "BlueBird Spotter.xcodeproj"`.
- Build from CLI: `xcodebuild -scheme "BlueBird Spotter" build`.
- Run tests from CLI: `xcodebuild -scheme "BlueBird Spotter" test` (requires an iOS Simulator destination; add `-destination 'platform=iOS Simulator,name=iPhone 15'` if needed).

## Coding Style & Naming Conventions
- Follow standard Swift/Xcode formatting (4-space indentation, one type per file).
- Type names use UpperCamelCase; properties and functions use lowerCamelCase.
- Match file names to the main type or view (e.g., `ContentView.swift`).
- Prefer Swift 6 concurrency primitives (`async/await`, `Task`, `@MainActor`) over legacy callback patterns.

## Testing Guidelines
- Unit tests use Swift Testing (`import Testing`) in `BlueBird SpotterTests/` with `@Test` functions.
- UI tests use XCTest in `BlueBird SpotterUITests/`, with methods prefixed `test...`.
- No coverage thresholds are configured; keep new logic covered when practical.
- Build the app after each change (`xcodebuild -scheme "BlueBird Spotter" build`) to verify changes compile.
- Run unit tests whenever you add or update tests or change logic they cover (`xcodebuild -scheme "BlueBird SpotterTests" test -destination 'platform=iOS Simulator,name=iPhone 15'`).
- Add or update unit tests for new features and logic where it makes sense to validate behavior.

## Commit & Pull Request Guidelines
- Git history is minimal (only “Initial Commit”), so no established message convention.
- Use short, imperative commit subjects (e.g., “Add TLE parsing”).
- PRs should include a brief summary, testing notes, and screenshots for UI changes.
