# Repository Guidelines

## IMPORTANT RULES:
- When you make changes, comment those changes or files with the guidlines in section: ## 6 Commenting Guidelines for Swift Files
- This project is for iOS and OS26
- keep ## 4 Testing Guidelines up to date when changes are made to Tests
- Project is swift 6. Be sure to use swift 6 concurrency throughout the entire project: https://developer.apple.com/documentation/swift/adoptingswift6
- Do not generate build/test artifacts inside the repository. Use $TMPDIR for DerivedData and xcresult output paths.
- Allowed dependency: SatelliteKit via SPM version 2.1.1

## 1 Project Structure & Module Organization
- `BlueBird Spotter/` holds the SwiftUI app source. Key folders: `App/` (entry point), `Views/`, `ViewModel/`, `Model/`, `Services/`, `Utilities/`.
- Assets live in `BlueBird Spotter/Assets/Assets.xcassets`.
- Tests are split into `BlueBird SpotterTests/` (unit) and `BlueBird SpotterUITests/` (UI).
- Xcode project metadata is in `BlueBird Spotter.xcodeproj`.

## 2 Build, Test, and Development Commands

### Open in Xcode
- `open "BlueBird Spotter.xcodeproj"`

### Build (CLI) — minimal artifacts
- Always write build artifacts outside the repository.
- `xcodebuild -scheme "BlueBird Spotter" build -derivedDataPath "$TMPDIR/BlueBirdSpotter-DerivedData"`

### Test (CLI) — minimal artifacts
- Always write test artifacts outside the repository.
- Default: do NOT generate an xcresult bundle unless explicitly needed.
- `xcodebuild -scheme "BlueBird Spotter" test -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath "$TMPDIR/BlueBirdSpotter-DerivedData"`

### Test (CLI) — with result bundle (only when debugging failures)
- `xcodebuild -scheme "BlueBird Spotter" test -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath "$TMPDIR/BlueBirdSpotter-DerivedData" -resultBundlePath "$TMPDIR/BlueBirdSpotter-TestResults.xcresult"`

### Cleanup (repo hygiene)
- If any artifacts appear in the repo, remove them:
- `rm -rf .derivedData* .test-results* *.xcresult`

## 3 Coding Style & Naming Conventions
- Follow standard Swift/Xcode formatting (4-space indentataion, one type per file).
- Type names use UpperCamelCase; properties and functions use lowerCamelCase.
- Match file names to the main type or view (e.g., `ContentView.swift`).

## 4 Testing Guidelines
- Unit tests use Swift Testing (`import Testing`) in `BlueBird SpotterTests/` with `@Test` functions.
- UI tests use XCTest in `BlueBird SpotterUITests/`, with methods prefixed `test...`.
- No coverage thresholds are configured; keep new logic covered when practical.

## 5 Commit & Pull Request Guidelines
- Git history is minimal (only “Initial Commit”), so no established message convention.
- Use short, imperative commit subjects (e.g., “Add TLE parsing”).
- PRs should include a brief summary, testing notes, and screenshots for UI changes.

## 6 Commenting Guidelines for Swift Files

This repository is designed for learning Swift and SwiftUI, so source comments should actively teach. When adding comments to new projects, follow these principles:

### 6.1 Overall Goals

- Explain **why** something is done, not just **what** the code literally does.
- Call out the **SwiftUI concept** being demonstrated (for example, implicit vs. explicit animations, state management, view composition).
- Keep comments concise but friendly, assuming the reader knows basic Swift syntax but may be new to the specific pattern.

### 6.2 Where to Comment

- **App entry point (`App` conformances):**
	- Add a brief doc comment explaining the purpose of the app and what the root view shows.
	- Example from `withAnimation_vs_animationApp`:

		```swift
		/// Entry point for the **withAnimation_vs_animation** demo app.
		///
		/// This app is intentionally small and focused. Its only job is to
		/// launch `ContentView`, which contains the side‑by‑side comparison
		/// of the two animation approaches.
		@main
		struct withAnimation_vs_animationApp: App { ... }
		```

- **Main container views (for example, `ContentView`):**
	- Use a doc comment to describe the overall layout and what the user can experiment with.
	- Inline comments for major sections (tabs, navigation, key layout containers) describing their role.

- **State and bindings (`@State`, `@Binding`, `@ObservedObject`, etc.):**
	- Add short comments that describe what behavior the state drives.
	- Focus on how changing the value affects the UI or animation.

- **Key demo views:**
	- Add a top-level doc comment explaining the **specific concept** the view demonstrates (for example, using `.animation(_:, value:)` vs. `withAnimation(_:_:)`).
	- Use a few targeted inline comments on the most important modifiers or closures, not every line.

- **Previews:**
	- Add a brief comment indicating what the preview is useful for (for example, "Preview for experimenting with the implicit animation approach.").

### 6.3 Comment Style

- Prefer **doc comments** (`///`) for types, properties, and top-level explanations.
- Use **inline comments** (`//`) sparingly to:
	- Separate logical sections inside a view body.
	- Explain surprising or non-obvious choices.
	- Highlight where a particular SwiftUI behavior is triggered (for example, where an animation is attached).
- Keep comments **high signal**:
	- Avoid restating the obvious (for example, `// This is a VStack` is not helpful).
	- Do explain concepts (`// Implicit animation: SwiftUI animates from the old width to the new width using this easing curve.`).

### 6.4 Tone and Audience

- Assume the reader is a **learner** exploring SwiftUI demos.
- Use positive, encouraging language and focus on what they can observe or tweak.
- Write in the third person, except when briefly addressing the reader (for example, "Here you can see…").

### 6.5 Example: Animation Demo

When documenting an animation-focused view (like `AnimatedView` / `WithAnimation`):

- At the **struct level**, explain what animation technique is being demonstrated.
- For the **state property**, mention how toggling it affects the UI.
- On the **core animated views**, add a comment that ties the modifier to the behavior the learner will see.
- Around **buttons or interaction points**, clarify whether the animation is declared on the view (`.animation`) or around the state change (`withAnimation`).

Example snippet inspired by `AnimatedView`:

```swift
/// Demonstrates using the `.animation(_:, value:)` view modifier.
///
/// Here each `Rectangle` has an animation attached directly to it.
/// Whenever `smallViews` changes, SwiftUI implicitly animates the
/// affected properties (the width in this case) to their new values.
struct AnimatedView: View {

		/// Tracks whether the rectangles should be "small" or "large".
		///
		/// Toggling this value drives the width change that we animate.
		@State private var smallViews: Bool = true

		var body: some View {
				VStack {
						// Red rectangle that animates its width when `smallViews` changes.
						Rectangle()
								.fill(.red)
								.frame(width: smallViews ? 200 : 100, height: 100)
								// Implicit animation: SwiftUI animates from the old
								// width to the new width using this easing curve.
								.animation(.easeInOut, value: smallViews)
						// ...
				}
		}
}
```
