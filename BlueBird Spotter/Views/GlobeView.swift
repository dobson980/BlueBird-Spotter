//
//  GlobeView.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/21/25.
//

import SwiftUI

/// Shows a 3D globe with tracked satellites and selection details.
struct GlobeView: View {
    /// Local tracking view model keeps the globe fed with positions.
    @State private var viewModel: TrackingViewModel
    /// Currently selected satellite for the detail overlay.
    @State private var selectedSatelliteId: Int?
    /// Shared navigation state for cross-tab focus.
    @Environment(AppNavigationState.self) private var navigationState
    /// Stores the persisted directional light toggle.
    @AppStorage("globe.light.directional.enabled") private var directionalLightEnabled = true
    /// Stores the persisted orbit path mode selection.
    @AppStorage("globe.orbit.mode") private var orbitPathModeRaw = OrbitPathMode.selectedOnly.rawValue
    /// Controls whether the globe settings panel is visible.
    @State private var isSettingsExpanded = false
    #if DEBUG
    /// Latest render diagnostics for debugging missing content.
    @State private var renderStats: GlobeRenderStats?
    #endif

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

    /// Allows previews to inject a prepared view model.
    init(viewModel: TrackingViewModel = TrackingViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            spaceBackground

            GlobeSceneView(
                trackedSatellites: viewModel.trackedSatellites,
                config: satelliteRenderConfig,
                selectedSatelliteId: selectedSatelliteId,
                isDirectionalLightEnabled: directionalLightEnabled,
                orbitPathMode: orbitPathMode,
                orbitPathConfig: OrbitPathConfig.default,
                focusRequest: navigationState.focusRequest,
                onStats: statsHandler,
                onSelect: { selectedSatelliteId = $0 }
            )
            // Let the globe fill under the status and tab bars for a more immersive view.
            .ignoresSafeArea(.container, edges: [.top, .bottom])

            if let selected = selectedSatellite {
                GlobeSelectionOverlay(trackedSatellite: selected)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            settingsButton
                .padding()
                // Safe-area padding keeps the floating control visible under the status bar cutout.
                .safeAreaPadding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if isSettingsExpanded {
                // A transparent scrim captures taps to dismiss the settings panel.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSettingsExpanded = false
                        }
                    }
            }

            if isSettingsExpanded {
                settingsPanel
                    .padding()
                    // Match the settings button by staying inside the top safe area.
                    .safeAreaPadding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            #if DEBUG
            if GlobeDebugFlags.showTuningUI {
                renderControls
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            if GlobeDebugFlags.showRenderStats {
                renderStatsOverlay
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            #endif
        }
        .task {
            guard !isPreview else { return }
            // Starts the tracking loop when the globe becomes active.
            viewModel.startTracking(queryKey: "SPACEMOBILE")
        }
        .onDisappear {
            // Cancels tracking to avoid background work when the tab is hidden.
            viewModel.stopTracking()
        }
        .onChange(of: navigationState.focusRequest?.token) { _ in
            // Mirror focus requests into selection so the overlay/high detail stays in sync.
            if let request = navigationState.focusRequest {
                selectedSatelliteId = request.satelliteId
            }
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
    /// Builds the live tuning overlay for scale and rotation offsets.
    private var renderControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Satellite Tuning")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Scale: \(satelliteScale, specifier: "%.3f")")
                Slider(value: $satelliteScale, in: 0.001...0.05)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Yaw Offset: \(satelliteBaseYawDegrees, specifier: "%.0f")°")
                Slider(value: $satelliteBaseYawDegrees, in: -180...180, step: 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Pitch Offset: \(satelliteBasePitchDegrees, specifier: "%.0f")°")
                Slider(value: $satelliteBasePitchDegrees, in: -180...180, step: 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Roll Offset: \(satelliteBaseRollDegrees, specifier: "%.0f")°")
                Slider(value: $satelliteBaseRollDegrees, in: -180...180, step: 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Orbit Heading: \(satelliteOrbitHeadingDegrees, specifier: "%.0f")°")
                Slider(value: $satelliteOrbitHeadingDegrees, in: -180...180, step: 1)
            }

            Toggle("Nadir Pointing", isOn: $satelliteNadirPointing)
            Toggle("Yaw Follows Orbit", isOn: $satelliteYawFollowsOrbit)

            Button("Reset") {
                resetRenderControls()
            }
        }
        .font(.caption)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Builds a lightweight debug readout for globe rendering stats.
    private var renderStatsOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Globe Stats")
                .font(.headline)
            Text("Tracked: \(viewModel.trackedSatellites.count)")
            Text("Nodes: \(renderStats?.nodeCount ?? 0)")
            Text("Template Loaded: \(renderStats?.templateLoaded == true ? "Yes" : "No")")
            Text("Uses Models: \(renderStats?.usesModelTemplates == true ? "Yes" : "No")")
            Text("Simulator: \(renderStats?.isSimulator == true ? "Yes" : "No")")
        }
        .font(.caption2)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

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

    /// Looks up the selected satellite for overlay display.
    private var selectedSatellite: TrackedSatellite? {
        guard let selectedSatelliteId else { return nil }
        return viewModel.trackedSatellites.first { $0.satellite.id == selectedSatelliteId }
    }

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

    /// Builds the top-right settings button for globe options.
    private var settingsButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSettingsExpanded.toggle()
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(10)
                .background(.thinMaterial, in: Circle())
        }
        .accessibilityLabel("Globe Settings")
    }

    /// Presents a compact settings card with globe-specific toggles.
    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Globe Settings")
                .font(.subheadline.weight(.semibold))

            Toggle("Directional Light", isOn: $directionalLightEnabled)

            VStack(alignment: .leading, spacing: 6) {
                Text("Orbit Paths")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Orbit Paths", selection: orbitPathModeBinding) {
                    ForEach(OrbitPathMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        .frame(maxWidth: 260)
    }

    /// Provides the debug stats callback when the build supports it.
    private var statsHandler: ((GlobeRenderStats) -> Void)? {
        #if DEBUG
        return { renderStats = $0 }
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

/// Overlay view that summarizes the tapped satellite.
private struct GlobeSelectionOverlay: View {
    let trackedSatellite: TrackedSatellite

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(trackedSatellite.satellite.name)
                .font(.headline)
            Text("Lat: \(formatDegrees(trackedSatellite.position.latitudeDegrees))")
            Text("Lon: \(formatDegrees(trackedSatellite.position.longitudeDegrees))")
            Text("Alt: \(formatKilometers(trackedSatellite.position.altitudeKm)) km")
        }
        .font(.caption)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    /// Rounds degrees for a compact overlay readout.
    private func formatDegrees(_ value: Double) -> String {
        String(format: "%.2f°", value)
    }

    /// Rounds kilometers for a compact overlay readout.
    private func formatKilometers(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

/// Preview for validating the globe overlay layout.
#Preview {
    GlobeView(viewModel: .previewModel())
}

private extension TrackingViewModel {
    /// Provides sample data for previewing the globe without network access.
    static func previewModel() -> TrackingViewModel {
        let viewModel = TrackingViewModel()
        let now = Date()
        let sampleSatellite = Satellite(
            id: 67890,
            name: "BLUEBIRD-XXX",
            tleLine1: "1 67890U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991",
            tleLine2: "2 67890  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456",
            epoch: now
        )
        let samplePosition = SatellitePosition(
            timestamp: now,
            latitudeDegrees: 12.34,
            longitudeDegrees: 56.78,
            altitudeKm: 550.2
        )
        let tracked = [TrackedSatellite(satellite: sampleSatellite, position: samplePosition)]
        viewModel.trackedSatellites = tracked
        viewModel.state = .loaded(tracked)
        viewModel.lastUpdatedAt = now
        return viewModel
    }
}
