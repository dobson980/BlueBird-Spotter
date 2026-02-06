# Contributing to BlueBird Spotter

Thanks for contributing to BlueBird Spotter.

## Development Setup

Requirements:
- Xcode 26+
- iOS 26+ simulator runtime (for tests)
- Swift 6 toolchain behavior (default in current project settings)

Open the project:

```bash
open "BlueBird Spotter.xcodeproj"
```

## Build and Test

Build with derived data outside the repository:

```bash
xcodebuild -scheme "BlueBird Spotter" build -derivedDataPath "$TMPDIR/BlueBirdSpotter-DerivedData"
```

Run tests (unit + UI) with artifacts outside the repository:

```bash
xcodebuild -scheme "BlueBird Spotter" test -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath "$TMPDIR/BlueBirdSpotter-DerivedData"
```

If an `.xcresult` bundle is needed for debugging, also pass:

```bash
-resultBundlePath "$TMPDIR/BlueBirdSpotter-TestResults.xcresult"
```

## Architecture Expectations

This repo uses MVVM + Services with a feature-first structure.

- `Views` handle presentation only.
- `ViewModels` manage UI state and orchestrate service calls.
- `Services` perform I/O, persistence, network, and system integration.
- `Core` contains shared domain logic and reusable utilities.

Please keep side effects out of SwiftUI views.

## Code Style

- Follow standard Swift formatting and naming conventions.
- Use Swift 6 concurrency patterns (`async/await`, actor-safe boundaries, cancellation-aware tasks).
- Add beginner-friendly comments when touching Swift files:
  - Explain what the code does.
  - Explain why the code exists.
  - Use plain English and short paragraphs.

## Pull Request Guidelines

Please include:
- A short summary of what changed and why.
- Testing notes (commands run and results).
- Screenshots for visible UI changes.

Try to keep PRs focused and reviewable. Smaller PRs are easier to validate and merge.
