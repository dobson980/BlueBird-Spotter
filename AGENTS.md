# Agents.md — Repository Guidelines (BlueBird Spotter)

These guidelines define how automated agents (and contributors) should change this repository.
The priorities are: correctness, readability, maintainability, and “open-source friendliness”.

---

## IMPORTANT RULES (Non-Negotiable)

- **Behavior-preserving refactors by default.** Do not change app behavior unless explicitly requested or a clear bug is found and documented.
- **Swift 6 concurrency is required.** Use modern Swift concurrency throughout the project. Reference: https://developer.apple.com/documentation/swift/adoptingswift6
- **Allowed dependency:** SatelliteKit via SPM, **version 2.1.1** only.
- **No build/test artifacts in the repo.** Write DerivedData and xcresult bundles to **$TMPDIR**.
- **Commenting is mandatory.** When you change or create files, follow **Section 6 — Commenting Guidelines**.
- **Keep Testing Guidelines current.** If tests are added/moved/changed, update **Section 4** accordingly.
- **Platforms:** This project targets **iOS** and **macOS 26+** (SwiftUI).  
  - Do not remove support for either platform without explicit instruction.
- **Services folder stays top-level.** Keep a repository-root folder named **`Services/`**.

---

## 1) Architecture & Project Structure

### 1.1 Target structure (feature-first, MVVM + Services)

This repository should be organized so a new contributor can find a feature quickly.
Use a **feature-first** layout, supported by shared `Core/` code and `Services/` for IO/side-effects.

**Target folders at repository root:**
- `App/` — app entry points and composition root wiring
- `Features/` — feature-first code organization
- `Core/` — shared UI components, shared domain logic, shared extensions
- `Services/` — IO, persistence, network, caching, background work (must remain top-level)
- `Resources/` — assets, localized strings, bundled resources (if separated)
- `Tests/` — optional “meta” location (see Section 4; existing Xcode test targets still apply)

> Note: The Xcode project may still show “BlueBird Spotter/…” groupings.
> Prefer aligning Xcode groups with the physical folder structure over time.

### 1.2 Feature folder standard

Each feature should follow this convention:

`Features/<FeatureName>/`
- `Views/` — SwiftUI views (presentation only)
- `ViewModels/` — MVVM state + orchestration
- `Models/` — feature-local models
- `Components/` — reusable UI pieces **local to the feature**
- `Scene/` or `Controllers/` — specialized rendering adapters/controllers (e.g., SceneKit wrappers)

### 1.3 Core folder standard (shared, pure, reusable)

`Core/` should contain shared code that is not a Service and not a specific feature:
- `Core/UI/Components/`
- `Core/UI/Modifiers/`
- `Core/UI/Styles/` (spacing, typography, etc.)
- `Core/Domain/Models/`
- `Core/Domain/Utilities/` (pure logic, math, parsing)
- `Core/Extensions/`

### 1.4 Services folder standard (must remain at repo root)

`Services/` is for side effects and IO:
- Network calls
- Disk persistence
- Caching policies
- Background refresh scheduling
- System integrations

`Services/` can be organized into subfolders:
- `Services/TLE/`
- `Services/Orbit/`
- `Services/System/`
- etc.

**Services must not import SwiftUI.**
Prefer protocol-backed service boundaries to enable unit testing.

---

## 2) MVVM + Services Boundary Rules

### 2.1 Views (SwiftUI)

Views should be “thin”:
- Allowed:
  - layout/composition
  - view modifiers
  - bindings (`@State`, `@Binding`, `@Environment`, `@ObservedObject`)
  - calling ViewModel intents/actions
  - small formatting helpers
- Not allowed:
  - network/disk access
  - parsing or caching logic
  - heavy math or algorithms
  - background refresh orchestration
  - long-lived timers/tasks
  - large state machines

**Rule of thumb:** If it’s not UI layout or trivial formatting, it probably doesn’t belong in a View.

### 2.2 ViewModels

ViewModels own:
- UI-facing state (`@Published`)
- derived state needed for rendering
- orchestration of Services
- task lifecycle + cancellation (Swift concurrency)
- debounce/throttle logic when needed

ViewModels should not:
- implement raw IO details
- contain complex algorithms that could be extracted to `Core/Domain`
- depend on SwiftUI types for business logic

### 2.3 Services

Services own:
- IO and side effects
- caching persistence
- OS/system integration
- background refresh scheduling

Services should:
- be protocol-backed when feasible (mockable)
- be dependency-injected into ViewModels (initializer injection is preferred)

---

## 3) Build, Test, and Development Commands (CLI)

### Open in Xcode
```bash
open "BlueBird Spotter.xcodeproj"
# Agents.md — Repository Guidelines (BlueBird Spotter)

These guidelines define how automated agents (and contributors) should change this repository.
The priorities are: correctness, readability, maintainability, and open-source friendliness.

---

## IMPORTANT RULES (Non-Negotiable)

- **Behavior-preserving refactors by default.** Do not change app behavior unless explicitly requested, or a clear bug is discovered and documented.
- **Swift 6 concurrency is required.** Use modern Swift concurrency throughout the project.
  - Reference: https://developer.apple.com/documentation/swift/adoptingswift6
- **Allowed dependency:** SatelliteKit via SPM, **version 2.1.1** only.
- **No build/test artifacts in the repo.** Write DerivedData and xcresult bundles to **$TMPDIR**.
- **Commenting is mandatory.** When you change or create files, follow **Section 6 — Commenting Guidelines**.
- **Keep Testing Guidelines current.** If tests are added, moved, renamed, or frameworks change, update **Section 4**.
- **Platforms:** This project targets **iOS** and **macOS 26+** (SwiftUI).
  - Do not remove support for either platform without explicit instruction.
- **Services folder stays top-level.** Keep a repository-root folder named **`Services/`**.

---

## 1) Architecture and Project Structure

### 1.1 Target structure (feature-first, MVVM + Services)

This repository should be organized so a new contributor can find a feature quickly.
Use a **feature-first** layout, supported by shared `Core/` code and `Services/` for IO and side effects.

**Target folders at repository root:**
- `App/` — app entry points and composition-root wiring
- `Features/` — feature-first code organization
- `Core/` — shared UI components, shared domain logic, shared extensions
- `Services/` — IO, persistence, network, caching, background work (must remain top-level)
- `Resources/` — assets, localized strings, bundled resources (if separated)
- `Tests/` — optional “meta” folder (the Xcode test targets still apply)

Notes:
- The Xcode project may still show “BlueBird Spotter/…” groups. Prefer aligning Xcode groups with the physical folder structure over time.
- This structure is the goal. Migrations can be incremental.

### 1.2 Feature folder standard

Each feature should follow this convention:

`Features/<FeatureName>/`
- `Views/` — SwiftUI views (presentation only)
- `ViewModels/` — MVVM state and orchestration
- `Models/` — feature-local models
- `Components/` — reusable UI pieces that are **local to the feature**
- `Scene/` or `Controllers/` — specialized rendering adapters/controllers (for example, SceneKit wrappers)

### 1.3 Core folder standard (shared, pure, reusable)

`Core/` should contain shared code that is not a Service and not a single feature:
- `Core/UI/Components/`
- `Core/UI/Modifiers/`
- `Core/UI/Styles/` (spacing, typography, etc.)
- `Core/Domain/Models/`
- `Core/Domain/Utilities/` (pure logic: math, parsing, algorithms)
- `Core/Extensions/`

### 1.4 Services folder standard (must remain at repo root)

`Services/` is for side effects and IO:
- network calls
- disk persistence
- caching policies
- background refresh scheduling
- system integrations

`Services/` may be organized into subfolders:
- `Services/TLE/`
- `Services/Orbit/`
- `Services/System/`
- and others as needed

Rules:
- Services **must not import SwiftUI**.
- Prefer protocol-backed boundaries where practical so services are mockable in unit tests.

---

## 2) MVVM + Services Boundary Rules

### 2.1 Views (SwiftUI)

Views should be thin.

Allowed in Views:
- layout and composition
- view modifiers
- bindings (`@State`, `@Binding`, `@Environment`, `@ObservedObject`, etc.)
- calling ViewModel intents/actions
- small formatting helpers

Not allowed in Views:
- network or disk access
- parsing or caching logic
- heavy math or algorithms
- background refresh orchestration
- long-lived timers/tasks
- large state machines

Rule of thumb: if it is not UI layout or trivial formatting, it likely does not belong in a View.

### 2.2 ViewModels

ViewModels own:
- UI-facing state (`@Published`)
- derived state needed for rendering
- orchestration of Services
- task lifecycle and cancellation (Swift concurrency)
- debounce/throttle logic when needed

ViewModels should not:
- implement raw IO details (that belongs in Services)
- contain complex algorithms that could be extracted to `Core/Domain`
- depend on SwiftUI types for business logic

### 2.3 Services

Services own:
- IO and side effects
- caching and persistence
- OS/system integration
- background refresh scheduling

Services should:
- be protocol-backed when feasible (mockable)
- be dependency-injected into ViewModels (initializer injection is preferred)

---

## 3) Build, Test, and Development Commands (CLI)

### Open in Xcode

```bash
open "BlueBird Spotter.xcodeproj"
```

### Build (CLI) — minimal artifacts

Always write build artifacts outside the repository.

```bash
xcodebuild \
  -scheme "BlueBird Spotter" \
  build \
  -derivedDataPath "$TMPDIR/BlueBirdSpotter-DerivedData"
```

### Test (CLI) — minimal artifacts

Default: do NOT generate an xcresult bundle unless debugging failures.

```bash
xcodebuild \
  -scheme "BlueBird Spotter" \
  test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath "$TMPDIR/BlueBirdSpotter-DerivedData"
```

### Test (CLI) — with result bundle (only when debugging failures)

```bash
xcodebuild \
  -scheme "BlueBird Spotter" \
  test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath "$TMPDIR/BlueBirdSpotter-DerivedData" \
  -resultBundlePath "$TMPDIR/BlueBirdSpotter-TestResults.xcresult"
```

### Cleanup (repo hygiene)

If any artifacts appear in the repo, remove them:

```bash
rm -rf .derivedData* .test-results* *.xcresult
```

---

## 4) Testing Guidelines

### 4.1 Test targets

- Unit tests live in `BlueBird SpotterTests/`.
- UI tests live in `BlueBird SpotterUITests/`.

### 4.2 Frameworks

- Unit tests use **Swift Testing** (`import Testing`) with `@Test` functions.
- UI tests use **XCTest** (`import XCTest`) with methods prefixed `test...`.

### 4.3 What to test (practical, high ROI)

Prioritize tests that protect logic and prevent regressions:
- ViewModel decisions:
  - selection rules
  - derived state
  - settings/toggle behavior
  - async orchestration and cancellation
- Core domain utilities:
  - parsers
  - math helpers
  - caching policy decisions

Avoid heavy UI snapshot testing unless already present and valuable.

### 4.4 Keep this section up to date

If tests are added, moved, renamed, or frameworks change, update this section.

---

## 5) Commit and Pull Request Guidelines

### 5.1 Commit style

Keep commits small and reviewable.
Prefer thematic commits in this general order:
1) `refactor(structure): ...` (moves only; behavior unchanged)
2) `refactor(<feature>): ...` (one offender/feature at a time)
3) `test: ...`
4) `docs: ...`
5) `ci: ...`

Commit subjects should be short, imperative, and specific.

### 5.2 PR expectations

PRs should include:
- short summary of what changed and why
- how you tested (commands and environments)
- screenshots only for UI changes
- explicit note about behavior changes (ideally “no behavior change”)

---

## 6) Commenting Guidelines (Teaching-Quality, Beginner-Friendly)

This repository is designed to be readable even by people with limited coding experience.
Comments should actively teach and reduce confusion.

### 6.1 Overall goals

- Explain **why** something is done, not just what the code literally does.
- Describe assumptions and tradeoffs.
- Connect the code to user-visible behavior.

### 6.2 Required comment coverage

When creating or changing code, include:
- a **file header** summary for new files:
  - what this file is responsible for
  - what it intentionally does NOT do
- **doc comments** (`///`) for:
  - public types
  - key ViewModels
  - key Services and service protocols
  - complex utility functions
- **inline comments** (`//`) for:
  - non-obvious logic
  - important safety checks
  - concurrency decisions
  - performance-related decisions

### 6.3 Tone and format

- Plain English.
- Short sentences.
- Short paragraphs.
- Avoid jargon; define it when needed.

### 6.4 Where to avoid comments

Do not comment the obvious:
- `// This is a VStack`
- `// Set the variable`

Comment intent and outcome instead.

### 6.5 Example comment style

```swift
/// Repository responsible for providing the latest TLE data.
///
/// Why this exists:
/// - Views and ViewModels should not know about HTTP requests or caching.
/// - We want one place to control how often we refresh.
///
/// What this does NOT do:
/// - It does not decide which satellites the user is tracking.
///   That is a UI / ViewModel decision.
protocol TLERepositoryProtocol {
    // ...
}
```

---

## 7) “Gross Offender” Refactor Rule (Large or Mixed-Responsibility Files)

Any file that is:
- over ~500 lines, OR
- mixes UI, orchestration, IO, and heavy logic

…must be evaluated for splitting.

### 7.1 Splitting playbook

1) Identify responsibilities:
   - UI composition
   - UI state/orchestration
   - IO/persistence/caching/background refresh
   - pure logic (math/parsing)
2) Extract by layer:
   - UI → `Features/<Feature>/Views` or `Features/<Feature>/Components`
   - orchestration/state → `Features/<Feature>/ViewModels`
   - IO/caching/background → `Services/<Domain>`
   - pure logic → `Core/Domain/Utilities`
3) Preserve behavior.
4) Add comments explaining what moved and why.

---

## 8) Documentation Requirements (Open Source)

### 8.1 README.md (required)

Maintain a root `README.md` that includes:
- what the app does
- platforms supported (iOS and macOS 26+)
- how to build and run
- dependency note (SatelliteKit 2.1.1)
- architecture overview (MVVM + Services, feature-first structure)
- where a new contributor should start

### 8.2 CONTRIBUTING.md (recommended)

Add and maintain a `CONTRIBUTING.md` that explains:
- how to build/test
- code style expectations (brief)
- PR guidelines

### 8.3 LICENSE

Ensure a LICENSE exists, or note that licensing is pending.

---

## 9) Concurrency and Safety (Swift 6)

- Prefer `async/await` and structured concurrency.
- Avoid ad-hoc thread hopping.
- Use `@MainActor` for UI-facing ViewModels and state.
- Avoid `Task.detached` unless justified in comments.
- When using `Task`, document cancellation behavior and why it matters.

---

## 10) Dependency Rules

- Allowed dependency: SatelliteKit via SPM version 2.1.1.
- Do not add new dependencies without explicit approval.

---