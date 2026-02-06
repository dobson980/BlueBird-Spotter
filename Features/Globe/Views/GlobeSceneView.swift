//
//  GlobeSceneView.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/21/25.
//

import QuartzCore
@preconcurrency import SceneKit
import SwiftUI
import simd

/// Snapshot of current render activity for debugging the globe view.
struct GlobeRenderStats: Equatable {
    /// Number of tracked satellites passed in from SwiftUI.
    let trackedCount: Int
    /// Number of nodes currently managed inside the SceneKit coordinator.
    let nodeCount: Int
    /// Indicates whether the renderer is attempting to use model templates.
    let usesModelTemplates: Bool
    /// Indicates whether the USDZ templates loaded successfully.
    let templateLoaded: Bool
    /// Reports whether the scene is running in the preview canvas.
    let isPreview: Bool
    /// Reports whether the scene is running in the simulator runtime.
    let isSimulator: Bool
}

/// Wraps an `SCNView` to display Earth and orbiting satellites.
struct GlobeSceneView: UIViewRepresentable {
    typealias Coordinator = GlobeSceneCoordinator
    /// Scene-space radius for Earth after normalization.
    static let earthRadiusScene: Float = 1.0
    /// Rotate the model so the prime meridian faces +Z when needed.
    static let earthPrimeMeridianRotation: Float = -.pi / 2
    /// Enables optional debug markers for orientation checks.
    static let showDebugMarkers = GlobeDebugFlags.showDebugMarkers
    /// Default intensity for the directional sun light.
    static let sunLightIntensity: CGFloat = 900
    /// Default intensity for the ambient fill light.
    static let ambientLightIntensity: CGFloat = 40
    /// Slightly brighter ambient when the directional light is disabled.
    static let ambientLightIntensityWhenDirectionalOff: CGFloat = 380
    /// Places the sunlight node far from Earth so it behaves like distant sunlight.
    static let sunLightNodeDistance: Float = 8
    /// Category mask used to render satellites.
    static let satelliteCategoryMask = 1 << 0
    /// Category mask used to render orbital paths.
    static let orbitPathCategoryMask = 1 << 1
    /// Combined mask for camera visibility (satellites + orbit paths).
    static let sceneContentCategoryMask = satelliteCategoryMask | orbitPathCategoryMask
    /// Maximum pitch angle used to keep the camera below the poles.
    /// Maximum camera pitch in degrees for SceneKit's camera controller.
    static let maxCameraPitchAngleDegrees: Float = 85
    /// Maximum camera pitch in radians for internal clamping math.
    static let maxCameraPitchAngleRadians: Float = 85 * .pi / 180

    /// Latest tracked satellite positions to render.
    let trackedSatellites: [TrackedSatellite]
    /// Render controls supplied by SwiftUI.
    let config: SatelliteRenderConfig
    /// Selected satellite id so the renderer can promote detail without a reset.
    let selectedSatelliteId: Int?
    /// Controls whether the directional light is enabled.
    let isDirectionalLightEnabled: Bool
    /// Controls which orbital paths are rendered.
    let orbitPathMode: OrbitPathMode
    /// Rendering configuration for orbital paths.
    let orbitPathConfig: OrbitPathConfig
    /// Optional focus request to center the camera on a satellite.
    let focusRequest: SatelliteFocusRequest?
    /// Optional debug hook for exposing render stats to SwiftUI overlays.
    let onStats: ((GlobeRenderStats) -> Void)?
    /// Notifies SwiftUI when the user taps a satellite node.
    let onSelect: (Int?) -> Void

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.antialiasingMode = .multisampling4X
        view.scene = makeScene()
        // Clear background so the SwiftUI space backdrop shows through.
        view.backgroundColor = UIColor.clear
        view.isOpaque = false
        view.allowsCameraControl = true
        view.cameraControlConfiguration.allowsTranslation = false
        // Turntable rotation keeps "up" fixed and feels like spinning a physical globe.
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.target = SCNVector3Zero
        // Limit vertical rotation to prevent flipping over the poles (degrees).
        let maxPitch = GlobeSceneView.maxCameraPitchAngleDegrees
        view.defaultCameraController.minimumVerticalAngle = -maxPitch
        view.defaultCameraController.maximumVerticalAngle = maxPitch
        view.autoenablesDefaultLighting = false
        // Force SceneKit to use our named camera so focus animations are visible.
        view.pointOfView = view.scene?.rootNode.childNode(withName: "globeCamera", recursively: false)

        // Remove SceneKit's built-in double-tap so our custom reset always fires.
        view.gestureRecognizers?
            .compactMap { $0 as? UITapGestureRecognizer }
            .filter { $0.numberOfTapsRequired == 2 }
            .forEach { view.removeGestureRecognizer($0) }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(GlobeSceneCoordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        // Double-tap resets the camera to the home position (0,0 over Africa).
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(GlobeSceneCoordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        view.addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)

        // Detect pan/pinch gestures to cancel any in-flight focus animations.
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(GlobeSceneCoordinator.handleInteraction(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(GlobeSceneCoordinator.handleInteraction(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        context.coordinator.view = view

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let scene = uiView.scene else { return }
        context.coordinator.renderConfig = config
        context.coordinator.selectionColor = orbitPathConfig.lineColor
        let lightingDate = trackedSatellites.first?.position.timestamp ?? Date()
        context.coordinator.updateLighting(
            in: scene,
            isDirectionalLightEnabled: isDirectionalLightEnabled,
            at: lightingDate
        )
        context.coordinator.updateSatellites(
            trackedSatellites,
            in: scene,
            selectedId: selectedSatelliteId
        )
        context.coordinator.updateCameraFocus(
            request: focusRequest,
            tracked: trackedSatellites,
            in: scene
        )
        context.coordinator.updateOrbitPaths(
            for: trackedSatellites,
            selectedId: selectedSatelliteId,
            mode: orbitPathMode,
            config: orbitPathConfig
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onStats: onStats, config: config)
    }

    /// Builds the base SceneKit scene with Earth, camera, and lighting.
    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        // Build the Earth model (fallback sphere for previews only).
        let earthNode = loadEarthNode(radiusScene: Self.earthRadiusScene)
        scene.rootNode.addChildNode(earthNode)

        if Self.showDebugMarkers {
            addDebugMarkers(to: scene, earthRadiusScene: Self.earthRadiusScene)
        }

        // Camera sits back far enough to see the full globe.
        let camera = SCNCamera()
        camera.zNear = 0.05
        camera.zFar = 12
        // Render both satellites and orbit paths (camera culls by category bit mask).
        camera.categoryBitMask = Self.sceneContentCategoryMask
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.name = "globeCamera"
        cameraNode.position = SCNVector3(0, 0, 3)
        // Point the camera at Earth initially. We avoid using SCNLookAtConstraint
        // because it conflicts with the arcball camera controller's inertia,
        // causing erratic behavior when the user releases a drag gesture.
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)

        // Lighting keeps the day/night contrast while letting night lights read.
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = Self.sunLightIntensity
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowRadius = 6
        sun.shadowColor = UIColor.black.withAlphaComponent(0.6)
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.name = "sunLight"
        sunNode.eulerAngles = SCNVector3(-0.6, 0.3, 0)
        scene.rootNode.addChildNode(sunNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = Self.ambientLightIntensity
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        ambientNode.name = "ambientLight"
        scene.rootNode.addChildNode(ambientNode)

        return scene
    }

    /// Loads the USDZ Earth model and normalizes it to the desired radius.
    private func loadEarthNode(radiusScene: Float) -> SCNNode {
        if Self.isRunningInPreview {
            // Previews prefer a lightweight sphere to avoid USDZ/Metal crashes.
            return makePreviewEarthSphere(radiusScene: radiusScene)
        }
        let earthRootNode = SCNNode()
        earthRootNode.name = "earthRoot"

        guard let url = Bundle.main.url(forResource: "Earth", withExtension: "usdz"),
              let referenceNode = SCNReferenceNode(url: url) else {
            return earthRootNode
        }

        referenceNode.load()
        if Self.shouldUseSafeMaterials {
            // Simulators often struggle with USDZ texture formats, so simplify materials.
            Self.applyPreviewSafeMaterials(to: referenceNode, color: .systemBlue)
        }
        earthRootNode.addChildNode(referenceNode)

        // Normalize the USDZ so its largest radius matches the scene radius.
        let (minBounds, maxBounds) = referenceNode.boundingBox
        let extent = SCNVector3(
            maxBounds.x - minBounds.x,
            maxBounds.y - minBounds.y,
            maxBounds.z - minBounds.z
        )
        let maxExtent = max(extent.x, max(extent.y, extent.z))
        let radius = maxExtent * 0.5
        if radius > 0 {
            let scale = radiusScene / radius
            earthRootNode.scale = SCNVector3(scale, scale, scale)
        }

        // Adjust orientation if the model's prime meridian needs alignment with +Z.
        earthRootNode.eulerAngles = SCNVector3(0, Self.earthPrimeMeridianRotation, 0)

        return earthRootNode
    }

    /// Adds marker spheres to verify orientation and coordinate mapping.
    private func addDebugMarkers(to scene: SCNScene, earthRadiusScene: Float) {
        let markers: [(String, Double, Double, UIColor)] = [
            ("Equator 0,0", 0, 0, .systemRed),
            ("Equator 0,90E", 0, 90, .systemGreen),
            ("North Pole", 90, 0, .systemBlue)
        ]

        for (label, lat, lon, color) in markers {
            let position = SatellitePosition(
                timestamp: Date(),
                latitudeDegrees: lat,
                longitudeDegrees: lon,
                altitudeKm: 0,
                velocityKmPerSec: nil
            )
            let node = SCNNode(geometry: SCNSphere(radius: 0.02))
            node.name = label
            node.geometry?.firstMaterial?.diffuse.contents = color
            node.position = GlobeCoordinateConverter.scenePosition(
                from: position,
                earthRadiusScene: earthRadiusScene
            )
            scene.rootNode.addChildNode(node)
            scene.rootNode.addChildNode(makeMarkerLabel(text: label, color: color, at: node.position))
        }
    }

    /// Creates a small billboard label so each debug marker is easy to identify in 3D.
    private func makeMarkerLabel(text: String, color: UIColor, at position: SCNVector3) -> SCNNode {
        let textGeometry = SCNText(string: text, extrusionDepth: 0.2)
        textGeometry.font = UIFont.systemFont(ofSize: 6, weight: .semibold)
        textGeometry.firstMaterial?.diffuse.contents = color
        textGeometry.firstMaterial?.isDoubleSided = true

        let textNode = SCNNode(geometry: textGeometry)
        textNode.scale = SCNVector3(0.003, 0.003, 0.003)
        textNode.position = SCNVector3(position.x, position.y + 0.04, position.z)

        // Billboard keeps the label facing the camera so it stays readable.
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y
        textNode.constraints = [billboard]

        return textNode
    }

    /// Builds a simple sphere Earth for preview stability in the canvas.
    private func makePreviewEarthSphere(radiusScene: Float) -> SCNNode {
        let earthNode = SCNNode(geometry: SCNSphere(radius: CGFloat(radiusScene)))
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemBlue
        material.lightingModel = .blinn
        earthNode.geometry?.materials = [material]
        return earthNode
    }

    /// Previews skip USDZ loading to avoid SceneKit/Metal crashes in the canvas.
    static var isRunningInPreview: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return true
        }
        return Bundle.main.bundlePath.contains("Previews")
    }

    /// Detects when the globe is running in the iOS simulator runtime.
    static var isRunningInSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Uses safer materials when the runtime is sensitive to USDZ texture formats.
    static var shouldUseSafeMaterials: Bool {
        isRunningInSimulator
    }

    /// Replaces USDZ materials with simple colors to avoid preview texture crashes.
    static func applyPreviewSafeMaterials(to rootNode: SCNNode, color: UIColor) {
        let applyMaterial: (SCNNode) -> Void = { node in
            guard let geometry = node.geometry else { return }
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.lightingModel = .blinn
            geometry.materials = [material]
        }

        applyMaterial(rootNode)
        rootNode.enumerateChildNodes { node, _ in
            applyMaterial(node)
        }
    }
}

/// Preview for validating the base globe rendering in a canvas-safe shell.
#Preview("Globe Only") {
    GlobeScenePreviewShell(
        trackedSatellites: [],
        selectedSatelliteId: nil,
        isDirectionalLightEnabled: true
    )
}

/// Preview for validating tracked-satellite rendering without orbit-ribbon artifacts.
#Preview("Tracked Satellites") {
    GlobeScenePreviewShell(
        trackedSatellites: GlobeScenePreviewFactory.sampleTrackedSatellites,
        selectedSatelliteId: GlobeScenePreviewFactory.sampleTrackedSatellites.first?.satellite.id,
        isDirectionalLightEnabled: true
    )
}

/// Shared preview shell that matches in-app dark styling and fills the preview canvas.
private struct GlobeScenePreviewShell: View {
    let trackedSatellites: [TrackedSatellite]
    let selectedSatelliteId: Int?
    let isDirectionalLightEnabled: Bool

    var body: some View {
        ZStack {
            // A simple dark gradient gives SceneKit a realistic context in preview.
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.06, blue: 0.11), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GlobeSceneView(
                trackedSatellites: trackedSatellites,
                config: SatelliteRenderConfig.debugDefaults,
                selectedSatelliteId: selectedSatelliteId,
                isDirectionalLightEnabled: isDirectionalLightEnabled,
                // Orbit ribbons are intentionally disabled in preview to keep the
                // canvas stable and avoid geometry artifacts that distract from
                // camera/light/material verification.
                orbitPathMode: .off,
                orbitPathConfig: .default,
                focusRequest: nil,
                onStats: nil,
                onSelect: { _ in }
            )
            .ignoresSafeArea()
        }
    }
}

/// Shared preview fixtures so SceneKit previews stay deterministic and readable.
private enum GlobeScenePreviewFactory {
    /// Stable sample satellites used by `GlobeSceneView` previews.
    static let sampleTrackedSatellites: [TrackedSatellite] = {
        let now = Date()
        let first = TrackedSatellite(
            satellite: Satellite(
                id: 45854,
                name: "BLUEBIRD-1",
                tleLine1: "1 45854U 20008A   26036.22192385  .00005457  00000+0  43089-3 0  9994",
                tleLine2: "2 45854  53.0544 292.8396 0001647  89.3122 270.8203 15.06378191327752",
                epoch: now
            ),
            position: SatellitePosition(
                timestamp: now,
                latitudeDegrees: 31.5,
                longitudeDegrees: -97.3,
                altitudeKm: 548.7,
                velocityKmPerSec: SIMD3(6.9, 1.8, 0.2)
            )
        )
        let second = TrackedSatellite(
            satellite: Satellite(
                id: 45955,
                name: "BLUEBIRD-2",
                tleLine1: "1 45955U 20040A   26036.13484363  .00004642  00000+0  37482-3 0  9998",
                tleLine2: "2 45955  53.0539 293.2265 0001579  90.5216 269.6102 15.06348287306616",
                epoch: now
            ),
            position: SatellitePosition(
                timestamp: now,
                latitudeDegrees: 18.2,
                longitudeDegrees: -32.6,
                altitudeKm: 546.1,
                velocityKmPerSec: SIMD3(6.7, 2.1, -0.3)
            )
        )
        return [first, second]
    }()
}
