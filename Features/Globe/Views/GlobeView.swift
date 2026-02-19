//
//  GlobeView.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/21/25.
//

import SwiftUI
import UIKit

/// Shows a 3D globe with tracked satellites and selection details.
struct GlobeView: View {
    /// Globe-specific view model manages selection, panel state, and tracking orchestration.
    @State private var viewModel: GlobeViewModel
    /// Shared navigation state for cross-tab focus.
    @Environment(AppNavigationState.self) private var navigationState
    /// Stores the persisted directional light toggle.
    @AppStorage("globe.light.directional.enabled") private var directionalLightEnabled = true
    /// Stores the persisted app-wide appearance preference.
    @AppStorage("app.appearance.mode") private var appAppearanceModeRaw = AppAppearanceMode.system.rawValue
    /// Stores the persisted orbit path mode selection.
    @AppStorage("globe.orbit.mode") private var orbitPathModeRaw = OrbitPathMode.selectedOnly.rawValue
    /// Stores the persisted orbit path thickness for the ribbon.
    @AppStorage("globe.orbit.thickness") private var orbitPathThickness: Double = 0.004
    /// Stores the persisted orbit path color selection.
    @AppStorage("globe.orbit.color") private var orbitPathColorId = OrbitPathColorOption.defaultId
    /// Stores the persisted coverage footprint mode selection.
    @AppStorage("globe.coverage.mode") private var coverageModeRaw = CoverageFootprintMode.selectedOnly.rawValue
    /// Query keys used for live tracking in the globe tab.
    private let queryKeys = SatelliteProgramCatalog.defaultQueryKeys
    /// A slightly longer animation keeps the glass settings panel from feeling "snappy" or jarring.
    private let settingsPanelAnimation: Animation = .smooth(duration: 0.35)

    #if DEBUG
    /// Adjusts the satellite model scale for SceneKit.
    @AppStorage("globe.satellite.scale") private var satelliteScale: Double = Double(SatelliteRenderConfig.debugDefaults.scale)
    /// Yaw offset (degrees) applied after the computed attitude.
    @AppStorage("globe.satellite.baseYawDegrees") private var satelliteBaseYawDegrees: Double = 0
    /// Pitch offset (degrees) applied after the computed attitude.
    @AppStorage("globe.satellite.basePitchDegrees") private var satelliteBasePitchDegrees: Double = 0
    /// Roll offset (degrees) applied after the computed attitude.
    @AppStorage("globe.satellite.baseRollDegrees") private var satelliteBaseRollDegrees: Double = 45
    /// Heading offset (degrees) applied around the radial axis.
    @AppStorage("globe.satellite.orbitHeadingDegrees") private var satelliteOrbitHeadingDegrees: Double = 45
    /// Enables nadir pointing so satellites face Earth.
    @AppStorage("globe.satellite.nadirPointing") private var satelliteNadirPointing = SatelliteRenderConfig.debugDefaults.nadirPointing
    /// Rotates the satellite around the radial axis to follow velocity.
    @AppStorage("globe.satellite.yawFollowsOrbit") private var satelliteYawFollowsOrbit = SatelliteRenderConfig.debugDefaults.yawFollowsOrbit
    #endif

    /// Builds a globe view using a tracking view model for live position updates.
    init(viewModel: TrackingViewModel = TrackingViewModel()) {
        _viewModel = State(initialValue: GlobeViewModel(trackingViewModel: viewModel))
    }

    /// Allows previews to inject a fully prepared globe view model state.
    init(globeViewModel: GlobeViewModel) {
        _viewModel = State(initialValue: globeViewModel)
    }

    var body: some View {
        ZStack {
            spaceBackground

            GlobeSceneView(
                trackedSatellites: viewModel.trackedSatellites,
                config: satelliteRenderConfig,
                selectedSatelliteId: viewModel.selectedSatelliteId,
                isDirectionalLightEnabled: directionalLightEnabled,
                orbitPathMode: orbitPathMode,
                orbitPathConfig: orbitPathConfig,
                coverageMode: coverageMode,
                focusRequest: navigationState.focusRequest,
                onStats: statsHandler,
                onSelect: { viewModel.selectedSatelliteId = $0 }
            )
            // Let the globe fill under the status and tab bars for a more immersive view.
            .ignoresSafeArea(.container, edges: [.top, .bottom])

            if let selected = viewModel.selectedSatellite {
                GlobeSelectionOverlay(trackedSatellite: selected)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // Keep camera gestures active while a satellite is selected.
                    .allowsHitTesting(false)
            }

            settingsButton
                .padding()
                // Safe-area padding keeps the floating control visible under the status bar cutout.
                .safeAreaPadding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if viewModel.isSettingsExpanded {
                // A transparent scrim captures taps to dismiss the settings panel.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(settingsPanelAnimation) {
                            viewModel.isSettingsExpanded = false
                        }
                    }
            }

            if viewModel.isSettingsExpanded {
                settingsPanel
                    .padding()
                    // Match the settings button by staying inside the top safe area.
                    .safeAreaPadding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            #if DEBUG
            if GlobeDebugFlags.showTuningUI {
                GlobeDebugRenderControls(
                    satelliteScale: $satelliteScale,
                    satelliteBaseYawDegrees: $satelliteBaseYawDegrees,
                    satelliteBasePitchDegrees: $satelliteBasePitchDegrees,
                    satelliteBaseRollDegrees: $satelliteBaseRollDegrees,
                    satelliteOrbitHeadingDegrees: $satelliteOrbitHeadingDegrees,
                    satelliteNadirPointing: $satelliteNadirPointing,
                    satelliteYawFollowsOrbit: $satelliteYawFollowsOrbit,
                    onReset: resetRenderControls
                )
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            if GlobeDebugFlags.showRenderStats {
                GlobeDebugStatsOverlay(
                    trackedCount: viewModel.trackedSatellites.count,
                    renderStats: viewModel.renderStats
                )
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            #endif
        }
        .task {
            guard !isPreview else { return }
            // Starts the tracking loop when the globe becomes active.
            viewModel.startTracking(queryKeys: queryKeys)
        }
        .onDisappear {
            // Reset transient HUD state so returning to globe starts clean.
            viewModel.dismissTransientPanels()
            // Cancels tracking to avoid background work when the tab is hidden.
            viewModel.stopTracking()
        }
        .onChange(of: navigationState.selectedTab) { _, selectedTab in
            guard selectedTab != .globe else { return }
            // Some tab transitions keep this view alive, so also clear overlays
            // when globe is no longer the active destination.
            viewModel.dismissTransientPanels()
        }
        .onChange(of: navigationState.focusRequest?.token) { _, _ in
            // Mirror focus requests into selection so the overlay/high detail stays in sync.
            viewModel.syncSelection(with: navigationState.focusRequest)
        }
    }

    /// Full-screen space backdrop shared across tabs.
    private var spaceBackground: some View {
        GeometryReader { geometry in
            Image("space")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .ignoresSafeArea()
    }

    /// Bundle all tuning knobs into a single config for SceneKit.
    private var satelliteRenderConfig: SatelliteRenderConfig {
        #if DEBUG
        SatelliteRenderConfig(
            useModel: true,
            scale: Float(satelliteScale),
            baseYaw: degreesToRadians(satelliteBaseYawDegrees),
            basePitch: degreesToRadians(satelliteBasePitchDegrees),
            baseRoll: degreesToRadians(satelliteBaseRollDegrees),
            nadirPointing: satelliteNadirPointing,
            yawFollowsOrbit: satelliteYawFollowsOrbit,
            orbitHeadingOffset: degreesToRadians(satelliteOrbitHeadingDegrees),
            detailMode: .lowWithHighForSelection,
            maxDetailModels: 1,
            lodDistances: SatelliteRenderConfig.debugDefaults.lodDistances
        )
        #else
        SatelliteRenderConfig.productionDefaults
        #endif
    }

    #if DEBUG
    /// Converts degree sliders into radians for SceneKit math.
    private func degreesToRadians(_ value: Double) -> Float {
        Float(value * .pi / 180)
    }

    /// Restores slider settings to a predictable baseline.
    private func resetRenderControls() {
        satelliteScale = Double(SatelliteRenderConfig.debugDefaults.scale)
        satelliteBaseYawDegrees = 0
        satelliteBasePitchDegrees = 0
        satelliteBaseRollDegrees = 0
        satelliteOrbitHeadingDegrees = 45
        satelliteNadirPointing = SatelliteRenderConfig.debugDefaults.nadirPointing
        satelliteYawFollowsOrbit = SatelliteRenderConfig.debugDefaults.yawFollowsOrbit
    }
    #endif

    /// Converts the persisted raw value into a user-facing orbit path mode.
    private var orbitPathMode: OrbitPathMode {
        OrbitPathMode(rawValue: orbitPathModeRaw) ?? .selectedOnly
    }

    /// Binds the orbit path mode to its persisted raw value.
    private var orbitPathModeBinding: Binding<OrbitPathMode> {
        Binding(
            get: { orbitPathMode },
            set: { orbitPathModeRaw = $0.rawValue }
        )
    }

    /// Converts the persisted raw value into a user-facing coverage mode.
    private var coverageMode: CoverageFootprintMode {
        CoverageFootprintMode(rawValue: coverageModeRaw) ?? .selectedOnly
    }

    /// Binds the coverage mode to its persisted raw value.
    private var coverageModeBinding: Binding<CoverageFootprintMode> {
        Binding(
            get: { coverageMode },
            set: { coverageModeRaw = $0.rawValue }
        )
    }

    /// Converts persisted raw storage into a safe app appearance enum.
    private var appAppearanceMode: AppAppearanceMode {
        AppAppearanceMode(rawValue: appAppearanceModeRaw) ?? .system
    }

    /// Binds app appearance mode selection to persisted raw storage.
    private var appAppearanceModeBinding: Binding<AppAppearanceMode> {
        Binding(
            get: { appAppearanceMode },
            set: { appAppearanceModeRaw = $0.rawValue }
        )
    }

    /// Returns the selected orbit color option, defaulting to ASTS orange.
    private var orbitPathColorOption: OrbitPathColorOption {
        OrbitPathColorOption.options.first { $0.id == orbitPathColorId } ?? OrbitPathColorOption.defaultOption
    }

    /// Builds the orbit path config from persisted settings.
    private var orbitPathConfig: OrbitPathConfig {
        let selected = orbitPathColorOption
        return OrbitPathConfig(
            sampleCount: OrbitPathConfig.default.sampleCount,
            altitudeOffsetKm: OrbitPathConfig.default.altitudeOffsetKm,
            lineColor: selected.uiColor,
            lineOpacity: OrbitPathConfig.default.lineOpacity,
            lineWidth: CGFloat(orbitPathThickness)
        )
    }

    /// Builds the top-right settings button with a glass style.
    private var settingsButton: some View {
        Button {
            withAnimation(settingsPanelAnimation) {
                // Clear selection when opening settings so the HUD does not compete for space.
                if !viewModel.isSettingsExpanded {
                    viewModel.selectedSatelliteId = nil
                }
                viewModel.isSettingsExpanded.toggle()
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Globe Settings")
    }

    /// Presents a compact settings card with globe-specific toggles.
    private var settingsPanel: some View {
        GlobeSettingsPanel(
            appAppearanceMode: appAppearanceModeBinding,
            directionalLightEnabled: $directionalLightEnabled,
            coverageMode: coverageModeBinding,
            orbitPathMode: orbitPathModeBinding,
            orbitPathThickness: $orbitPathThickness,
            orbitPathColorId: $orbitPathColorId
        )
    }

    /// Provides the debug stats callback when the build supports it.
    private var statsHandler: ((GlobeRenderStats) -> Void)? {
        #if DEBUG
        return { viewModel.renderStats = $0 }
        #else
        return nil
        #endif
    }

    /// Detects when the view is running in Xcode previews.
    private var isPreview: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return true
        }
        return Bundle.main.bundlePath.contains("Previews")
    }
}

/// Preview for validating the default globe composition.
#Preview("Default") {
    GlobeView(globeViewModel: .previewDefault())
        // Inject navigation state so focus and selection bindings resolve in preview.
        .environment(AppNavigationState())
}

/// Preview for validating the selection overlay card style and values.
#Preview("Selection Overlay") {
    GlobeView(globeViewModel: .previewWithSelection())
        .environment(AppNavigationState())
}

/// Preview for validating the settings panel layout and control spacing.
#Preview("Settings Panel") {
    GlobeView(globeViewModel: .previewWithSettingsExpanded())
        .environment(AppNavigationState())
}

private extension GlobeViewModel {
    /// Baseline preview state with tracked satellites and no modal UI.
    static func previewDefault() -> GlobeViewModel {
        GlobeViewModel(trackingViewModel: .previewLoadedModel())
    }

    /// Preview state that forces one selected satellite for overlay validation.
    static func previewWithSelection() -> GlobeViewModel {
        let viewModel = GlobeViewModel(trackingViewModel: .previewLoadedModel())
        viewModel.selectedSatelliteId = TrackingViewModel.previewTrackedSatellites.first?.satellite.id
        return viewModel
    }

    /// Preview state that opens the settings panel for quick control iteration.
    static func previewWithSettingsExpanded() -> GlobeViewModel {
        let viewModel = GlobeViewModel(trackingViewModel: .previewLoadedModel())
        viewModel.isSettingsExpanded = true
        return viewModel
    }
}
