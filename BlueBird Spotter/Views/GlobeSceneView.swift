//
//  GlobeSceneView.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/21/25.
//

import QuartzCore
import SatKit
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
    /// Scene-space radius for Earth after normalization.
    private static let earthRadiusScene: Float = 1.0
    /// Rotate the model so the prime meridian faces +Z when needed.
    private static let earthPrimeMeridianRotation: Float = -.pi / 2
    /// Enables optional debug markers for orientation checks.
    private static let showDebugMarkers = GlobeDebugFlags.showDebugMarkers
    /// Default intensity for the directional sun light.
    private static let sunLightIntensity: CGFloat = 900
    /// Default intensity for the ambient fill light.
    private static let ambientLightIntensity: CGFloat = 40
    /// Slightly brighter ambient when the directional light is disabled.
    private static let ambientLightIntensityWhenDirectionalOff: CGFloat = 380
    /// Category mask used to render satellites.
    private static let satelliteCategoryMask = 1 << 0
    /// Category mask used to render orbital paths.
    private static let orbitPathCategoryMask = 1 << 1
    /// Combined mask for camera visibility (satellites + orbit paths).
    private static let sceneContentCategoryMask = satelliteCategoryMask | orbitPathCategoryMask
    /// Maximum pitch angle used to keep the camera below the poles.
    /// Maximum camera pitch in degrees for SceneKit's camera controller.
    private static let maxCameraPitchAngleDegrees: Float = 85
    /// Maximum camera pitch in radians for internal clamping math.
    private static let maxCameraPitchAngleRadians: Float = 85 * .pi / 180

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

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        // Double-tap resets the camera to the home position (0,0 over Africa).
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        view.addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)

        // Detect pan/pinch gestures to cancel any in-flight focus animations.
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleInteraction(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleInteraction(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        context.coordinator.view = view

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let scene = uiView.scene else { return }
        context.coordinator.renderConfig = config
        context.coordinator.updateLighting(in: scene, isDirectionalLightEnabled: isDirectionalLightEnabled)
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

    /// Coordinator stores satellite nodes to avoid re-creating geometry each tick.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Identifies which model template a satellite is currently using.
        private enum DetailTier {
            case high
            case low
        }

        /// Category mask used for satellite hit testing.
        private let satelliteCategoryMask = GlobeSceneView.satelliteCategoryMask
        /// Category mask used for orbital path visuals.
        private let orbitPathCategoryMask = GlobeSceneView.orbitPathCategoryMask
        /// Limits how many orbit paths build concurrently to keep the UI responsive.
        private static let maxConcurrentOrbitPathBuilds = 2

        private var satelliteNodes: [Int: SCNNode] = [:]
        private var lastPositions: [Int: SCNVector3] = [:]
        /// Cached orientation quaternions to smooth per-tick updates.
        private var lastOrientation: [Int: simd_quatf] = [:]
        /// Cached right-axis vectors to stabilize yaw when velocity is noisy.
        private var lastRightAxis: [Int: simd_float3] = [:]
        /// Timestamp of the most recent tracking tick for interpolation.
        private var lastTickTimestamp: Date?
        /// Cached animation duration for smooth position updates.
        private var lastAnimationDuration: TimeInterval = 0
        /// Tracks which detail tier each satellite node is using.
        private var nodeDetailTiers: [Int: DetailTier] = [:]
        /// High-detail template generated from the USDZ model.
        private var satelliteHighTemplateNode: SCNNode?
        /// Low-detail template that reuses simplified materials.
        private var satelliteLowTemplateNode: SCNNode?
        /// Last LOD distances applied to the high-detail geometry.
        private var lastLodDistances: [Float] = []
        /// Tracks whether the USDZ templates are currently in use.
        private var currentUseModel = false
        /// Tracks which nodes are currently using model geometry for scaling.
        private var nodeUsesModel: [Int: Bool] = [:]
        /// Last scale applied to model nodes so we avoid redundant updates.
        private var lastScale: Float?
        /// Remembers whether yaw-following was enabled last tick to reset caches.
        private var lastYawFollowsOrbit: Bool?
        /// Tracks the last applied directional light state to avoid redundant work.
        private var lastDirectionalLightEnabled: Bool?
        /// Cached orbital path nodes keyed by shared orbital signatures.
        private var orbitPathNodes: [OrbitSignature: SCNNode] = [:]
        /// In-flight orbit path build tasks.
        private var orbitPathTasks: [OrbitSignature: Task<[SIMD3<Float>], Never>] = [:]
        /// Remembers the last orbit path config to refresh when settings change.
        private var lastOrbitPathConfig: OrbitPathConfig?
        /// Remembers the active sample count so we can rebuild when it changes.
        private var lastOrbitPathSampleCount: Int?
        /// Latest Earth-rotation alignment applied to orbit path nodes.
        private var lastOrbitRotation: simd_quatf?
        /// Tracks the most recent camera focus request token.
        private var lastFocusToken: UUID?
        /// Stores a focus request until the satellite node exists.
        private var pendingFocusRequest: SatelliteFocusRequest?
        /// Action key used to replace in-flight camera focus animations.
        private let cameraFocusActionKey = "cameraFocusOrbit"
        /// Home camera position for double-tap reset (0,0 over Africa).
        private let homeCameraPosition = SCNVector3(0, 0, 3)
        /// Latest tuning knobs from SwiftUI.
        var renderConfig: SatelliteRenderConfig
        private let onSelect: (Int?) -> Void
        private let onStats: ((GlobeRenderStats) -> Void)?
        weak var view: SCNView?
        private weak var cameraNode: SCNNode?

        init(
            onSelect: @escaping (Int?) -> Void,
            onStats: ((GlobeRenderStats) -> Void)?,
            config: SatelliteRenderConfig
        ) {
            self.onSelect = onSelect
            self.onStats = onStats
            self.renderConfig = config
        }

        /// Updates positions in place and removes nodes for missing satellites.
        func updateSatellites(
            _ tracked: [TrackedSatellite],
            in scene: SCNScene,
            selectedId: Int?
        ) {
            if cameraNode == nil {
                cameraNode = scene.rootNode.childNode(withName: "globeCamera", recursively: false)
            }
            var shouldUseModel = renderConfig.useModel && !GlobeSceneView.isRunningInPreview
            if shouldUseModel {
                loadSatelliteTemplates()
                shouldUseModel = satelliteHighTemplateNode != nil
            }
            if shouldUseModel != currentUseModel {
                resetSatelliteNodes()
                currentUseModel = shouldUseModel
            }

            if lastYawFollowsOrbit != renderConfig.yawFollowsOrbit {
                // Clear cached axes so we don't keep velocity-based roll when toggling modes.
                lastRightAxis.removeAll()
                lastOrientation.removeAll()
                lastYawFollowsOrbit = renderConfig.yawFollowsOrbit
            }

            updateLodIfNeeded()

            let ids = Set(tracked.map { $0.satellite.id })
            for (id, node) in satelliteNodes where !ids.contains(id) {
                node.removeFromParentNode()
                satelliteNodes[id] = nil
                lastPositions[id] = nil
                lastOrientation[id] = nil
                lastRightAxis[id] = nil
                nodeDetailTiers[id] = nil
                nodeUsesModel[id] = nil
            }

            let tickTimestamp = tracked.first?.position.timestamp
            let previousTickTimestamp = lastTickTimestamp
            let animationDuration: TimeInterval
            if let tickTimestamp, let previousTickTimestamp {
                let delta = tickTimestamp.timeIntervalSince(previousTickTimestamp)
                animationDuration = max(0, min(delta, 1.5))
            } else {
                animationDuration = 0
            }
            lastTickTimestamp = tickTimestamp
            lastAnimationDuration = animationDuration
            let hasNewTick = tickTimestamp != nil && tickTimestamp != previousTickTimestamp

            var updates: [(id: Int, node: SCNNode, position: SCNVector3, trackedSatellite: TrackedSatellite)] = []
            updates.reserveCapacity(tracked.count)

            for trackedSatellite in tracked {
                let id = trackedSatellite.satellite.id
                let desiredTier = resolveDetailTier(
                    for: id,
                    selectedId: selectedId,
                    allowModel: shouldUseModel
                )
                let node = satelliteNodes[id] ?? makeSatelliteNode(
                    for: trackedSatellite,
                    in: scene,
                    allowModel: shouldUseModel,
                    detailTier: desiredTier
                )
                if nodeDetailTiers[id] != desiredTier {
                    // Swap the model tier without recreating the node to avoid selection jitter.
                    applyDetailTier(desiredTier, to: node, id: id)
                    nodeDetailTiers[id] = desiredTier
                }
                let position = GlobeCoordinateConverter.scenePosition(
                    from: trackedSatellite.position,
                    earthRadiusScene: GlobeSceneView.earthRadiusScene
                )
                updates.append((id: id, node: node, position: position, trackedSatellite: trackedSatellite))
            }

            // Animate positions so satellites glide between 1Hz tracking ticks.
            SCNTransaction.begin()
            SCNTransaction.disableActions = animationDuration == 0
            SCNTransaction.animationDuration = animationDuration
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .linear)
            for update in updates {
                update.node.position = update.position
            }
            SCNTransaction.commit()

            // Update orientation and scale without implicit SceneKit animations.
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            let shouldApplyScale = lastScale != renderConfig.scale
            for update in updates {
                if hasNewTick || lastOrientation[update.id] == nil {
                    // Only recompute attitude when we receive a new ephemeris tick.
                    // This prevents selection taps from briefly snapping the model
                    // to a fallback axis when the position hasn't advanced yet.
                    applyOrientation(
                        for: update.id,
                        node: update.node,
                        currentPosition: update.position,
                        trackedSatellite: update.trackedSatellite
                    )
                }
                if shouldUseModel, nodeUsesModel[update.id] == true {
                    let scale = renderConfig.scale
                    if shouldApplyScale || update.node.scale.x != scale {
                        applyModelScale(scale, to: update.node)
                    }
                }
            }
            SCNTransaction.commit()

            if shouldUseModel {
                lastScale = renderConfig.scale
            }

            publishStats(trackedCount: tracked.count, shouldUseModel: shouldUseModel)
        }

        /// Updates directional and ambient lighting based on user settings.
        func updateLighting(in scene: SCNScene, isDirectionalLightEnabled: Bool) {
            guard lastDirectionalLightEnabled != isDirectionalLightEnabled else { return }
            lastDirectionalLightEnabled = isDirectionalLightEnabled

            let sunNode = scene.rootNode.childNode(withName: "sunLight", recursively: false)
            let ambientNode = scene.rootNode.childNode(withName: "ambientLight", recursively: false)

            if isDirectionalLightEnabled {
                sunNode?.light?.intensity = GlobeSceneView.sunLightIntensity
                sunNode?.light?.castsShadow = true
                ambientNode?.light?.intensity = GlobeSceneView.ambientLightIntensity
            } else {
                sunNode?.light?.intensity = 0
                sunNode?.light?.castsShadow = false
                ambientNode?.light?.intensity = GlobeSceneView.ambientLightIntensityWhenDirectionalOff
            }
        }

        /// Centers the camera on a satellite when a focus request is issued.
        func updateCameraFocus(
            request: SatelliteFocusRequest?,
            tracked _: [TrackedSatellite],
            in scene: SCNScene
        ) {
            if let request, lastFocusToken != request.token {
                lastFocusToken = request.token
                pendingFocusRequest = request
            }

            guard let pending = pendingFocusRequest else { return }
            guard let targetNode = satelliteNodes[pending.satelliteId] else { return }

            // Ensure we have the camera node reference.
            if cameraNode == nil {
                cameraNode = scene.rootNode.childNode(withName: "globeCamera", recursively: false)
            }
            guard let cameraNode = cameraNode else { return }
            view?.pointOfView = cameraNode

            // Get the direction from Earth's center to the satellite.
            let satellitePosition = targetNode.position
            let posX = satellitePosition.x
            let posY = satellitePosition.y
            let posZ = satellitePosition.z

            // Validate position is not NaN or zero.
            guard posX.isFinite && posY.isFinite && posZ.isFinite else {
                pendingFocusRequest = nil
                return
            }

            let directionLength = sqrt(posX * posX + posY * posY + posZ * posZ)
            guard directionLength > 0.001 else {
                pendingFocusRequest = nil
                return
            }

            // Normalize to get direction from Earth center toward satellite.
            let targetDirection = simd_float3(
                posX / directionLength,
                posY / directionLength,
                posZ / directionLength
            )

            // Position camera at the same distance as home position.
            let desiredDistance: Float = 3.0

            animateCameraOrbit(
                to: targetDirection,
                distance: desiredDistance,
                node: cameraNode
            )

            pendingFocusRequest = nil
        }

        /// Animates the camera to look at a specific direction on the globe.
        ///
        /// The camera travels along an arc around the Earth rather than through it,
        /// using spherical linear interpolation (slerp) to maintain constant distance.
        /// For satellites on opposite sides, we pick a consistent intermediate path.
        private func animateCameraOrbit(
            to targetDirection: simd_float3,
            distance: Float,
            node: SCNNode
        ) {
            // Clamp the target direction to stay within vertical angle limits.
            let maxPitch = GlobeSceneView.maxCameraPitchAngleRadians
            let clampedDirection = clampDirectionToVerticalLimits(targetDirection, maxPitch: maxPitch)

            // Validate end direction is finite.
            guard clampedDirection.x.isFinite && clampedDirection.y.isFinite && clampedDirection.z.isFinite else {
                return
            }

            // Get current camera position and compute start direction.
            let startX = node.position.x
            let startY = node.position.y
            let startZ = node.position.z

            // Validate start position is finite, otherwise use home position.
            let safeStartX = startX.isFinite ? startX : 0
            let safeStartY = startY.isFinite ? startY : 0
            let safeStartZ = startZ.isFinite ? startZ : 3.0

            let startPos = simd_float3(safeStartX, safeStartY, safeStartZ)
            let startLength = simd_length(startPos)
            let startDirection: simd_float3
            if startLength > 0.001 {
                startDirection = startPos / startLength
            } else {
                startDirection = simd_float3(0, 0, 1)
            }

            // Calculate angle between start and end directions.
            let dot = simd_clamp(simd_dot(startDirection, clampedDirection), -1.0, 1.0)
            let angle = acos(dot)

            // For nearly opposite directions (> 150°), we need to pick a consistent
            // intermediate direction to avoid ambiguity. We'll rotate horizontally
            // (around Y axis) to keep the motion predictable.
            let needsIntermediate = angle > 2.6 // ~150 degrees
            let intermediateDirection: simd_float3
            if needsIntermediate {
                // Create a perpendicular direction in the XZ plane.
                // Cross product of start with Y-up gives a horizontal perpendicular.
                let yUp = simd_float3(0, 1, 0)
                var perp = simd_cross(startDirection, yUp)
                let perpLen = simd_length(perp)
                if perpLen > 0.001 {
                    perp = perp / perpLen
                } else {
                    // Start is pointing straight up/down, use Z axis.
                    perp = simd_float3(0, 0, 1)
                }
                // Blend start direction toward this perpendicular, staying at equator-ish level.
                let midY = (startDirection.y + clampedDirection.y) * 0.5
                let horizontalScale = sqrt(max(0.01, 1.0 - midY * midY))
                intermediateDirection = simd_normalize(simd_float3(perp.x * horizontalScale, midY, perp.z * horizontalScale))
            } else {
                intermediateDirection = simd_float3(0, 0, 0) // Not used.
            }

            node.removeAction(forKey: cameraFocusActionKey)

            let duration: TimeInterval = needsIntermediate ? 0.6 : 0.45
            let action = SCNAction.customAction(duration: duration) { [startDirection, clampedDirection, intermediateDirection, needsIntermediate, distance] actionNode, time in
                let t = Float(time / CGFloat(duration))
                // Smooth-step easing.
                let easedT = t * t * (3.0 - 2.0 * t)

                let interpolatedDirection: simd_float3
                if needsIntermediate {
                    // Two-phase slerp: start -> intermediate -> end.
                    if easedT < 0.5 {
                        let segmentT = easedT * 2.0
                        interpolatedDirection = Self.slerp(from: startDirection, to: intermediateDirection, t: segmentT)
                    } else {
                        let segmentT = (easedT - 0.5) * 2.0
                        interpolatedDirection = Self.slerp(from: intermediateDirection, to: clampedDirection, t: segmentT)
                    }
                } else {
                    interpolatedDirection = Self.slerp(from: startDirection, to: clampedDirection, t: easedT)
                }

                // Compute position at constant distance from origin.
                let x = interpolatedDirection.x * distance
                let y = interpolatedDirection.y * distance
                let z = interpolatedDirection.z * distance

                // Final safety check.
                if x.isFinite && y.isFinite && z.isFinite {
                    actionNode.position = SCNVector3(x, y, z)
                    // Manually compute orientation to avoid look(at:) flip issues.
                    Self.orientCameraTowardOrigin(actionNode)
                }
            }
            node.runAction(action, forKey: cameraFocusActionKey)
        }

        /// Spherical linear interpolation between two unit vectors.
        nonisolated private static func slerp(from a: simd_float3, to b: simd_float3, t: Float) -> simd_float3 {
            let dot = simd_clamp(simd_dot(a, b), -1.0, 1.0)
            let angle = acos(dot)

            if angle < 0.001 {
                // Nearly identical, just return the target.
                return b
            }

            let sinAngle = sin(angle)
            let weightA = sin((1.0 - t) * angle) / sinAngle
            let weightB = sin(t * angle) / sinAngle
            return a * weightA + b * weightB
        }

        /// Points the camera at the origin while maintaining Y-up orientation.
        nonisolated private static func orientCameraTowardOrigin(_ node: SCNNode) {
            let position = node.position
            // Forward direction (camera looks down -Z in its local space).
            let forward = simd_normalize(simd_float3(-position.x, -position.y, -position.z))

            // World up vector.
            let worldUp = simd_float3(0, 1, 0)

            // Right vector = forward × up (then normalize).
            var right = simd_cross(forward, worldUp)
            let rightLen = simd_length(right)
            if rightLen > 0.001 {
                right = right / rightLen
            } else {
                // Looking straight up or down, pick arbitrary right.
                right = simd_float3(1, 0, 0)
            }

            // Recalculate up to ensure orthogonality.
            let up = simd_cross(right, forward)

            // Build rotation matrix (column-major for SceneKit).
            // SceneKit camera looks down -Z, so forward = -Z, right = X, up = Y.
            let rotationMatrix = simd_float4x4(columns: (
                simd_float4(right.x, right.y, right.z, 0),
                simd_float4(up.x, up.y, up.z, 0),
                simd_float4(-forward.x, -forward.y, -forward.z, 0),
                simd_float4(0, 0, 0, 1)
            ))

            node.simdTransform = simd_float4x4(columns: (
                rotationMatrix.columns.0,
                rotationMatrix.columns.1,
                rotationMatrix.columns.2,
                simd_float4(position.x, position.y, position.z, 1)
            ))
        }

        /// Clamps a direction vector so it doesn't exceed the vertical angle limits.
        ///
        /// This keeps the camera from going directly over the poles where turntable
        /// mode becomes unstable. Returns a unit-length direction vector.
        nonisolated private func clampDirectionToVerticalLimits(
            _ direction: simd_float3,
            maxPitch: Float
        ) -> simd_float3 {
            let length = simd_length(direction)
            guard length > 0.0001, length.isFinite else {
                // Fallback: face Africa from the front.
                return simd_float3(0, 0, 1)
            }

            let normalized = direction / length

            // Guard against NaN values in input.
            guard normalized.x.isFinite && normalized.y.isFinite && normalized.z.isFinite else {
                return simd_float3(0, 0, 1)
            }

            // Y component determines vertical angle (pitch).
            // sin(pitch) = y, so clamp y to sin(maxPitch).
            let maxY = sin(maxPitch)
            let clampedY = max(-maxY, min(maxY, normalized.y))

            // Reconstruct the horizontal components to maintain unit length.
            let horizontalScale = sqrt(max(0, 1 - clampedY * clampedY))
            let originalHorizontal = simd_float2(normalized.x, normalized.z)
            let originalHorizontalLength = simd_length(originalHorizontal)

            let clampedHorizontal: simd_float2
            if originalHorizontalLength > 0.0001 {
                clampedHorizontal = (originalHorizontal / originalHorizontalLength) * horizontalScale
            } else {
                // If looking straight up/down, default to facing Africa (positive Z).
                clampedHorizontal = simd_float2(0, horizontalScale)
            }

            let result = simd_float3(clampedHorizontal.x, clampedY, clampedHorizontal.y)

            // Final validation: ensure result is a valid unit vector.
            let resultLength = simd_length(result)
            if resultLength > 0.99 && resultLength < 1.01 && result.x.isFinite && result.y.isFinite && result.z.isFinite {
                return result
            } else {
                // Fallback if something went wrong.
                return simd_float3(0, 0, 1)
            }
        }

        /// Renders orbital paths based on the selected mode, deduping shared orbits.
        func updateOrbitPaths(
            for tracked: [TrackedSatellite],
            selectedId: Int?,
            mode: OrbitPathMode,
            config: OrbitPathConfig
        ) {
            if lastOrbitPathConfig != config {
                clearOrbitPaths()
                lastOrbitPathConfig = config
            }

            let referenceDate = tracked.first?.position.timestamp ?? Date()
            applyOrbitRotation(for: referenceDate)

            let signaturesById = buildOrbitSignatures(from: tracked)
            let representative = buildRepresentativeSatellites(from: tracked, signatures: signaturesById)
            let desiredSignatures: Set<OrbitSignature>

            switch mode {
            case .off:
                desiredSignatures = []
            case .selectedOnly:
                if let selectedId,
                   let signature = signaturesById[selectedId] {
                    desiredSignatures = [signature]
                } else {
                    desiredSignatures = []
                }
            case .all:
                desiredSignatures = Set(signaturesById.values)
            }

            let effectiveSampleCount = orbitPathSampleCount(
                for: mode,
                desiredCount: desiredSignatures.count,
                baseSampleCount: config.sampleCount
            )
            if lastOrbitPathSampleCount != effectiveSampleCount {
                clearOrbitPaths()
                lastOrbitPathSampleCount = effectiveSampleCount
            }

            removeOrbitPaths(excluding: desiredSignatures)
            buildMissingOrbitPaths(
                desired: desiredSignatures,
                representative: representative,
                config: config,
                referenceDate: referenceDate,
                sampleCount: effectiveSampleCount,
                priority: mode == .all ? .utility : .userInitiated
            )
        }

        /// Handles taps by hit-testing SceneKit nodes.
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = view else { return }
            let point = gesture.location(in: view)
            let hits = view.hitTest(point, options: [
                SCNHitTestOption.categoryBitMask: satelliteCategoryMask
            ])
            guard let hitNode = hits.first?.node else {
                onSelect(nil)
                return
            }

            onSelect(resolveSatelliteId(from: hitNode))
        }

        /// Resets the camera to the home position (0,0 over Africa) on double-tap.
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = view,
                  let scene = view.scene else { return }

            // Ensure we have the camera node reference.
            if cameraNode == nil {
                cameraNode = scene.rootNode.childNode(withName: "globeCamera", recursively: false)
            }
            guard let cameraNode = cameraNode else { return }
            view.pointOfView = cameraNode
            view.defaultCameraController.target = SCNVector3Zero

            cameraNode.removeAction(forKey: cameraFocusActionKey)

            // Use the same orbit animation to smoothly return to the home position.
            let homeDirection = simd_normalize(simd_float3(homeCameraPosition.x, homeCameraPosition.y, homeCameraPosition.z))
            let homeDistance = simd_length(simd_float3(homeCameraPosition.x, homeCameraPosition.y, homeCameraPosition.z))

            animateCameraOrbit(
                to: homeDirection,
                distance: homeDistance,
                node: cameraNode
            )
        }

        /// Cancels any in-flight camera focus animation when the user starts dragging or zooming.
        @objc func handleInteraction(_ gesture: UIGestureRecognizer) {
            if gesture.state == .began {
                // Stop the focus animation so it doesn't fight with the user's gesture.
                cameraNode?.removeAction(forKey: cameraFocusActionKey)
            }
        }

        /// Allows our gesture recognizers to work alongside SceneKit's built-in camera gestures.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Allow all our gesture recognizers to fire alongside SceneKit's camera controller.
            return true
        }

        /// Ensures our tap/double-tap recognizers aren't blocked by SceneKit's internal gestures.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Let our own gestures fire without waiting on SceneKit's defaults.
            return false
        }

        /// Creates a satellite node, using USDZ when available and storing it for reuse.
        private func makeSatelliteNode(
            for tracked: TrackedSatellite,
            in scene: SCNScene,
            allowModel: Bool,
            detailTier: DetailTier
        ) -> SCNNode {
            let node: SCNNode
            if allowModel, let modelNode = loadTemplateNode(for: detailTier)?.clone() {
                // Use the model node directly so its pivot stays aligned with the satellite origin.
                node = modelNode
                nodeDetailTiers[tracked.satellite.id] = detailTier
                nodeUsesModel[tracked.satellite.id] = true
            } else {
                let geometry = SCNSphere(radius: 0.015)
                let material = SCNMaterial()
                material.diffuse.contents = UIColor.systemYellow
                geometry.materials = [material]
                let sphereNode = SCNNode(geometry: geometry)
                node = sphereNode
                nodeDetailTiers[tracked.satellite.id] = .low
                nodeUsesModel[tracked.satellite.id] = false
            }

            let name = String(tracked.satellite.id)
            applyName(name, to: node)
            applyCategory(satelliteCategoryMask, to: node)

            scene.rootNode.addChildNode(node)
            satelliteNodes[tracked.satellite.id] = node
            return node
        }

        /// Loads and caches high/low USDZ templates for cloning.
        private func loadSatelliteTemplates() {
            guard satelliteHighTemplateNode == nil || satelliteLowTemplateNode == nil else { return }
            guard let url = Bundle.main.url(forResource: "BlueBird", withExtension: "usdz"),
                  let referenceNode = SCNReferenceNode(url: url) else {
                return
            }
            referenceNode.load()
            tuneSatelliteMaterials(referenceNode)
            if GlobeSceneView.shouldUseSafeMaterials {
                // Simulators use flat materials to avoid USDZ texture format issues.
                GlobeSceneView.applyPreviewSafeMaterials(to: referenceNode, color: .systemYellow)
            }

            // Prefer a flattened clone for performance, but fall back to the full
            // reference node if the flattening step produces no geometry.
            let flattened = referenceNode.flattenedClone()
            let flattenedGeometry = flattened.geometry ?? firstGeometry(in: flattened)
            let flattenedExtent = maxExtent(for: flattened)
            let highContent: SCNNode
            let sourceGeometry: SCNGeometry?
            if let flattenedGeometry, flattenedExtent > 0.001 {
                highContent = flattened
                sourceGeometry = flattenedGeometry
            } else {
                let fallback = referenceNode.clone()
                highContent = fallback
                sourceGeometry = fallback.geometry ?? firstGeometry(in: fallback)
            }

            guard sourceGeometry != nil else {
                // If no geometry is available, allow the caller to fall back to spheres.
                satelliteHighTemplateNode = nil
                satelliteLowTemplateNode = nil
                return
            }

            let highNode = SCNNode()
            highNode.addChildNode(highContent)

            // Center the pivot so rotations happen around the model's center of mass.
            let (minBounds, maxBounds) = highContent.boundingBox
            let center = SCNVector3(
                (minBounds.x + maxBounds.x) * 0.5,
                (minBounds.y + maxBounds.y) * 0.5,
                (minBounds.z + maxBounds.z) * 0.5
            )
            // SceneKit pivots are applied before transforms, so negate to move the center to origin.
            highNode.pivot = SCNMatrix4MakeTranslation(-center.x, -center.y, -center.z)

            let lowNode = makeLowDetailTemplate(from: highNode)

            satelliteHighTemplateNode = highNode
            satelliteLowTemplateNode = lowNode
            lastLodDistances = []
            updateLodIfNeeded()
        }

        /// Returns the cached template for the requested detail tier.
        private func loadTemplateNode(for tier: DetailTier) -> SCNNode? {
            loadSatelliteTemplates()
            switch tier {
            case .high:
                return satelliteHighTemplateNode
            case .low:
                return satelliteLowTemplateNode
            }
        }

        /// Builds a low-detail template by simplifying materials while keeping transforms intact.
        private func makeLowDetailTemplate(from highNode: SCNNode) -> SCNNode {
            let lowNode = highNode.clone()
            // Clone geometry so simplifying materials does not mutate the high-detail template.
            lowNode.enumerateChildNodes { node, _ in
                guard let geometry = node.geometry?.copy() as? SCNGeometry else { return }
                node.geometry = geometry
                Self.applySimplifiedMaterials(to: geometry, color: .systemYellow)
            }
            if let geometry = lowNode.geometry?.copy() as? SCNGeometry {
                lowNode.geometry = geometry
                Self.applySimplifiedMaterials(to: geometry, color: .systemYellow)
            }
            return lowNode
        }

        /// Applies a simplified material set while keeping the original diffuse texture.
        ///
        /// This preserves the visual identity of the satellite without the cost of
        /// normal/roughness/metalness maps that are expensive at large counts.
        private static func applySimplifiedMaterials(to geometry: SCNGeometry, color: UIColor) {
            let sourceMaterial = geometry.materials.first
            let material = SCNMaterial()
            material.diffuse.contents = sourceMaterial?.diffuse.contents ?? color
            material.lightingModel = .blinn
            material.emission.contents = nil
            material.normal.contents = nil
            material.roughness.contents = nil
            material.metalness.contents = nil
            material.ambientOcclusion.contents = nil
            material.transparencyMode = .aOne
            geometry.materials = [material]
        }

        /// Finds the first geometry in a node hierarchy for LOD assignment.
        private func firstGeometry(in node: SCNNode) -> SCNGeometry? {
            if let geometry = node.geometry {
                return geometry
            }
            for child in node.childNodes {
                if let geometry = firstGeometry(in: child) {
                    return geometry
                }
            }
            return nil
        }

        /// Computes the largest extent of a node's bounding box for size sanity checks.
        private func maxExtent(for node: SCNNode) -> Float {
            let (minBounds, maxBounds) = node.boundingBox
            let extent = SCNVector3(
                maxBounds.x - minBounds.x,
                maxBounds.y - minBounds.y,
                maxBounds.z - minBounds.z
            )
            return max(extent.x, max(extent.y, extent.z))
        }

        /// Updates LOD thresholds if the render config changes.
        private func updateLodIfNeeded() {
            guard lastLodDistances != renderConfig.lodDistances else { return }
            lastLodDistances = renderConfig.lodDistances
            guard let highTemplate = satelliteHighTemplateNode else { return }
            guard let firstDistance = renderConfig.lodDistances.first else {
                applyLod(nil, to: highTemplate)
                return
            }
            let distance = max(firstDistance, 0.01)
            // LOD keeps the model visible while swapping to simplified materials at distance.
            applyLod(distance, to: highTemplate)
        }

        /// Applies a material-only LOD to all geometries in the template.
        private func applyLod(_ distance: Float?, to node: SCNNode) {
            let applyToGeometry: (SCNGeometry) -> Void = { geometry in
                if let distance {
                    let lowGeometry = geometry.copy() as? SCNGeometry ?? geometry
                    Self.applySimplifiedMaterials(to: lowGeometry, color: .systemYellow)
                    geometry.levelsOfDetail = [
                        SCNLevelOfDetail(geometry: lowGeometry, worldSpaceDistance: CGFloat(distance))
                    ]
                } else {
                    geometry.levelsOfDetail = nil
                }
            }

            if let geometry = node.geometry {
                applyToGeometry(geometry)
            }
            node.enumerateChildNodes { child, _ in
                if let geometry = child.geometry {
                    applyToGeometry(geometry)
                }
            }
        }

        /// Chooses which model tier a satellite should use.
        private func resolveDetailTier(
            for id: Int,
            selectedId: Int?,
            allowModel: Bool
        ) -> DetailTier {
            guard allowModel else { return .low }
            switch renderConfig.detailMode {
            case .lowOnly:
                return .low
            case .lowWithHighForSelection:
                guard renderConfig.maxDetailModels > 0 else { return .low }
                return id == selectedId ? .high : .low
            }
        }

        /// Swaps the model child node to match the desired detail tier.
        private func applyDetailTier(_ tier: DetailTier, to node: SCNNode, id: Int) {
            guard let template = loadTemplateNode(for: tier)?.clone() else { return }
            // Swap the model contents in-place so the satellite keeps its transform.
            node.childNodes.forEach { $0.removeFromParentNode() }
            node.geometry = template.geometry
            node.pivot = template.pivot
            for child in template.childNodes {
                node.addChildNode(child)
            }
            applyName(node.name ?? "", to: node)
            nodeUsesModel[id] = true
        }

        /// Applies the render scale to model children without affecting the parent position.
        private func applyModelScale(_ scale: Float, to node: SCNNode) {
            let scaleVector = SCNVector3(scale, scale, scale)
            if !matchesScale(node.scale, scaleVector) {
                node.scale = scaleVector
            }
        }

        /// Removes all cached orbit paths and cancels in-flight builds.
        private func clearOrbitPaths() {
            for node in orbitPathNodes.values {
                node.removeFromParentNode()
            }
            orbitPathNodes.removeAll()
            for task in orbitPathTasks.values {
                task.cancel()
            }
            orbitPathTasks.removeAll()
        }

        /// Builds a map of satellite ids to their deduped orbit signatures.
        private func buildOrbitSignatures(from tracked: [TrackedSatellite]) -> [Int: OrbitSignature] {
            var signatures: [Int: OrbitSignature] = [:]
            for trackedSatellite in tracked {
                if let signature = OrbitSignature(tleLine2: trackedSatellite.satellite.tleLine2) {
                    signatures[trackedSatellite.satellite.id] = signature
                }
            }
            return signatures
        }

        /// Picks a single representative satellite for each shared orbit signature.
        private func buildRepresentativeSatellites(
            from tracked: [TrackedSatellite],
            signatures: [Int: OrbitSignature]
        ) -> [OrbitSignature: Satellite] {
            var representatives: [OrbitSignature: Satellite] = [:]
            for trackedSatellite in tracked {
                guard let signature = signatures[trackedSatellite.satellite.id] else { continue }
                if representatives[signature] == nil {
                    representatives[signature] = trackedSatellite.satellite
                }
            }
            return representatives
        }

        /// Removes orbit paths that are no longer required by the active mode.
        private func removeOrbitPaths(excluding desired: Set<OrbitSignature>) {
            for (signature, node) in orbitPathNodes where !desired.contains(signature) {
                node.removeFromParentNode()
                orbitPathNodes[signature] = nil
            }
            for (signature, task) in orbitPathTasks where !desired.contains(signature) {
                task.cancel()
                orbitPathTasks[signature] = nil
            }
        }

        /// Builds missing orbital paths asynchronously for the requested signatures.
        private func buildMissingOrbitPaths(
            desired: Set<OrbitSignature>,
            representative: [OrbitSignature: Satellite],
            config: OrbitPathConfig,
            referenceDate: Date,
            sampleCount: Int,
            priority: TaskPriority
        ) {
            let altitudeOffsetKm = config.altitudeOffsetKm

            for signature in desired {
                if orbitPathTasks.count >= Self.maxConcurrentOrbitPathBuilds {
                    break
                }
                guard orbitPathNodes[signature] == nil,
                      orbitPathTasks[signature] == nil,
                      let satellite = representative[signature] else { continue }

                let task = Task.detached(priority: priority) {
                    return Self.buildOrbitPathVertices(
                        for: satellite,
                        referenceDate: referenceDate,
                        sampleCount: sampleCount,
                        altitudeOffsetKm: altitudeOffsetKm
                    )
                }

                orbitPathTasks[signature] = task

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let vertices = await task.value
                    self.orbitPathTasks[signature] = nil

                    guard !Task.isCancelled,
                          self.orbitPathNodes[signature] == nil,
                          desired.contains(signature),
                          vertices.count > 1 else { return }

                    guard let config = self.lastOrbitPathConfig else { return }
                    let node = self.makeOrbitPathNode(vertices: vertices, config: config)
                    if let rotation = self.lastOrbitRotation {
                        node.simdOrientation = rotation
                    }
                    self.view?.scene?.rootNode.addChildNode(node)
                    self.orbitPathNodes[signature] = node
                }
            }
        }

        /// Aligns orbit path nodes with the current Earth rotation angle.
        private func applyOrbitRotation(for date: Date) {
            let gmstRadians = EarthCoordinateConverter.gmstRadians(for: date)
            // Rotate inertial (TEME) paths into the Earth-fixed frame used by the globe.
            let rotation = simd_quatf(angle: Float(-gmstRadians), axis: simd_float3(0, 1, 0))
            lastOrbitRotation = rotation
            for node in orbitPathNodes.values {
                node.simdOrientation = rotation
            }
        }

        /// Creates a SceneKit node for an orbital path line strip.
        private func makeOrbitPathNode(vertices: [SIMD3<Float>], config: OrbitPathConfig) -> SCNNode {
            let geometry = buildOrbitPathGeometry(vertices: vertices, config: config)
            let material = SCNMaterial()
            material.diffuse.contents = config.lineColor
            material.emission.contents = config.lineColor
            material.transparency = config.lineOpacity
            material.isDoubleSided = true
            material.writesToDepthBuffer = false
            material.readsFromDepthBuffer = true
            geometry.materials = [material]

            let node = SCNNode(geometry: geometry)
            // Orbit paths are visual-only; keep them out of satellite hit testing.
            node.categoryBitMask = orbitPathCategoryMask
            return node
        }

        /// Builds either a thin line or a ribbon geometry based on the configured thickness.
        private func buildOrbitPathGeometry(vertices: [SIMD3<Float>], config: OrbitPathConfig) -> SCNGeometry {
            let lineWidth = Float(config.lineWidth)
            if lineWidth > 0.0005 {
                return buildOrbitRibbonGeometry(vertices: vertices, width: lineWidth)
            }
            return buildOrbitLineGeometry(vertices: vertices)
        }

        /// Builds a thin line geometry for the orbit path.
        private func buildOrbitLineGeometry(vertices: [SIMD3<Float>]) -> SCNGeometry {
            let scnVertices = vertices.map { SCNVector3($0.x, $0.y, $0.z) }
            let source = SCNGeometrySource(vertices: scnVertices)
            let indices = buildLineIndices(count: scnVertices.count)
            let element = SCNGeometryElement(indices: indices, primitiveType: .line)
            return SCNGeometry(sources: [source], elements: [element])
        }

        /// Builds a ribbon-style orbit path so thickness is adjustable.
        private func buildOrbitRibbonGeometry(vertices: [SIMD3<Float>], width: Float) -> SCNGeometry {
            guard vertices.count > 1 else {
                return buildOrbitLineGeometry(vertices: vertices)
            }

            let halfWidth = width * 0.5
            var ribbonVertices: [SCNVector3] = []
            ribbonVertices.reserveCapacity(vertices.count * 2)

            for index in vertices.indices {
                let current = vertices[index]
                let previous = index > 0 ? vertices[index - 1] : current
                let next = index + 1 < vertices.count ? vertices[index + 1] : current

                let tangentRaw = next - previous
                let tangentLength = simd_length(tangentRaw)
                let tangent = tangentLength > 0.0001
                    ? (tangentRaw / tangentLength)
                    : simd_float3(1, 0, 0)

                let radialRaw = current
                let radialLength = simd_length(radialRaw)
                let radial = radialLength > 0.0001
                    ? (radialRaw / radialLength)
                    : simd_float3(0, 1, 0)

                var side = simd_cross(tangent, radial)
                if simd_length(side) < 0.0001 {
                    side = simd_cross(tangent, simd_float3(0, 1, 0))
                }
                if simd_length(side) < 0.0001 {
                    side = simd_cross(radial, simd_float3(1, 0, 0))
                }
                side = simd_normalize(side)

                let offset = side * halfWidth
                let left = current + offset
                let right = current - offset
                ribbonVertices.append(SCNVector3(left.x, left.y, left.z))
                ribbonVertices.append(SCNVector3(right.x, right.y, right.z))
            }

            let indices = (0..<UInt32(ribbonVertices.count)).map { $0 }
            let source = SCNGeometrySource(vertices: ribbonVertices)
            let element = SCNGeometryElement(indices: indices, primitiveType: .triangleStrip)
            return SCNGeometry(sources: [source], elements: [element])
        }

        /// Builds the index list for consecutive line segments.
        private func buildLineIndices(count: Int) -> [UInt32] {
            guard count > 1 else { return [] }
            var indices: [UInt32] = []
            indices.reserveCapacity((count - 1) * 2)
            for index in 0..<(count - 1) {
                indices.append(UInt32(index))
                indices.append(UInt32(index + 1))
            }
            return indices
        }

        /// Chooses a lighter sample count when many paths are requested at once.
        private func orbitPathSampleCount(
            for mode: OrbitPathMode,
            desiredCount: Int,
            baseSampleCount: Int
        ) -> Int {
            guard mode == .all else { return baseSampleCount }
            if desiredCount > 150 {
                return max(40, baseSampleCount / 4)
            }
            if desiredCount > 60 {
                return max(60, baseSampleCount / 2)
            }
            return baseSampleCount
        }

        /// Computes orbit path vertices in scene space without touching SceneKit types.
        private nonisolated static func buildOrbitPathVertices(
            for satellite: Satellite,
            referenceDate: Date,
            sampleCount: Int,
            altitudeOffsetKm: Double
        ) -> [SIMD3<Float>] {
            guard sampleCount > 1,
                  let meanMotion = Self.parseMeanMotion(from: satellite.tleLine2),
                  meanMotion > 0,
                  let elements = try? SatKit.Elements(satellite.name, satellite.tleLine1, satellite.tleLine2) else {
                return []
            }

            let propagator = SatKit.selectPropagatorLegacy(elements)
            let epochDate = Date(ds1950: elements.t₀)
            let periodSeconds = 86400.0 / meanMotion
            let step = periodSeconds / Double(sampleCount)

            var vertices: [SIMD3<Float>] = []
            vertices.reserveCapacity(sampleCount + 1)

            for index in 0..<sampleCount {
                if Task.isCancelled { break }
                let date = referenceDate.addingTimeInterval(Double(index) * step)
                let minutesSinceEpoch = date.timeIntervalSince(epochDate) / 60.0
                guard let pvCoordinates = try? propagator.getPVCoordinates(minsAfterEpoch: minutesSinceEpoch) else {
                    continue
                }

                let temePosition = SIMD3(
                    pvCoordinates.position.x / 1000.0,
                    pvCoordinates.position.y / 1000.0,
                    pvCoordinates.position.z / 1000.0
                )
                let radiusKm = max(simd_length(temePosition), GlobeCoordinateConverter.earthRadiusKm)
                let adjustedRadius = max(GlobeCoordinateConverter.earthRadiusKm, radiusKm - altitudeOffsetKm)
                let normalized = temePosition / radiusKm
                let adjustedPosition = normalized * adjustedRadius

                let scale = GlobeCoordinateConverter.defaultScale
                // Map TEME axes to the scene axes used by GlobeCoordinateConverter:
                // TEME x -> scene z, TEME y -> scene x, TEME z -> scene y.
                vertices.append(
                    SIMD3<Float>(
                        Float(adjustedPosition.y * scale),
                        Float(adjustedPosition.z * scale),
                        Float(adjustedPosition.x * scale)
                    )
                )
            }

            // Close the loop so the orbit reads as a continuous path.
            if let first = vertices.first {
                vertices.append(first)
            }
            return vertices
        }

        /// Extracts mean motion from TLE line 2 without touching main-actor state.
        private nonisolated static func parseMeanMotion(from line: String) -> Double? {
            guard line.count >= 63 else { return nil }
            let start = line.index(line.startIndex, offsetBy: 52)
            let end = line.index(line.startIndex, offsetBy: 62)
            let substring = line[start...end].trimmingCharacters(in: .whitespaces)
            return Double(substring)
        }

        /// Emits render diagnostics for debug overlays.
        private func publishStats(trackedCount: Int, shouldUseModel: Bool) {
            guard let onStats else { return }
            let stats = GlobeRenderStats(
                trackedCount: trackedCount,
                nodeCount: satelliteNodes.count,
                usesModelTemplates: shouldUseModel,
                templateLoaded: satelliteHighTemplateNode != nil,
                isPreview: GlobeSceneView.isRunningInPreview,
                isSimulator: GlobeSceneView.isRunningInSimulator
            )
            onStats(stats)
        }

        /// Compares SceneKit vectors without relying on Equatable conformance.
        private func matchesScale(_ lhs: SCNVector3, _ rhs: SCNVector3) -> Bool {
            lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z
        }

        /// Computes orientation so the model points toward Earth and optionally along velocity.
        private func applyOrientation(
            for id: Int,
            node: SCNNode,
            currentPosition: SCNVector3,
            trackedSatellite: TrackedSatellite
        ) {
            defer { lastPositions[id] = currentPosition }

            let config = renderConfig
            let baseOffset = baseOrientationQuaternion(for: config)
            guard config.nadirPointing else {
                node.simdOrientation = baseOffset
                lastOrientation[id] = baseOffset
                return
            }

            let position = currentPosition.simd
            let distance = simd_length(position)
            guard distance > 0 else {
                node.simdOrientation = baseOffset
                lastOrientation[id] = baseOffset
                return
            }

            // Model forward is assumed to be -Z, so +Z points away from Earth.
            let outward = position / distance
            let radial = -outward

            let right = preferredRightAxis(
                for: id,
                radial: radial,
                outward: outward,
                currentPosition: currentPosition,
                trackedSatellite: trackedSatellite
            )
            let up = simd_normalize(simd_cross(outward, right))

            let basis = simd_float3x3(columns: (right, up, outward))
            let orientation = simd_quatf(basis)

            // Apply a heading offset around the radial axis to align the long face with the orbit line.
            let headingOffset = config.orbitHeadingOffset
            let headingRotation = headingOffset == 0
                ? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
                : simd_quatf(angle: headingOffset, axis: outward)
            // Apply base offsets after attitude so artists can correct model alignment.
            let targetOrientation = headingRotation * orientation * baseOffset
            if let last = lastOrientation[id] {
                // Slerp smooths orientation changes to prevent visible snapping on tick boundaries.
                node.simdOrientation = simd_slerp(last, targetOrientation, 0.35)
            } else {
                node.simdOrientation = targetOrientation
            }
            lastOrientation[id] = node.simdOrientation
        }

        /// Picks a stable right axis, favoring velocity tangent when enabled.
        ///
        /// Uses the provided SGP4 velocity on the first tick so satellites load with
        /// the correct orbit-following orientation immediately. Subsequent ticks use
        /// position delta for smoother tracking.
        private func preferredRightAxis(
            for id: Int,
            radial: simd_float3,
            outward: simd_float3,
            currentPosition: SCNVector3,
            trackedSatellite: TrackedSatellite
        ) -> simd_float3 {
            if renderConfig.yawFollowsOrbit {
                // Try position-based velocity first (more stable for animation).
                if let previous = lastPositions[id] {
                    let velocity = (currentPosition - previous).simd
                    let velocityLength = simd_length(velocity)
                    if velocityLength > 0 {
                        let velocityDir = velocity / velocityLength
                        let projected = velocityDir - radial * simd_dot(velocityDir, radial)
                        if simd_length(projected) > 0.0001 {
                            var stabilized = simd_normalize(projected)
                            if let cached = lastRightAxis[id], simd_dot(stabilized, cached) < 0 {
                                stabilized = -stabilized
                            }
                            lastRightAxis[id] = stabilized
                            return stabilized
                        }
                    }
                }

                // First tick: use SGP4-provided velocity for correct initial orientation.
                if let velocityKmPerSec = trackedSatellite.position.velocityKmPerSec {
                    let velocityDir = GlobeCoordinateConverter.sceneVelocityDirection(
                        from: velocityKmPerSec,
                        at: trackedSatellite.position.timestamp
                    )
                    let projected = velocityDir - radial * simd_dot(velocityDir, radial)
                    if simd_length(projected) > 0.0001 {
                        var stabilized = simd_normalize(projected)
                        if let cached = lastRightAxis[id], simd_dot(stabilized, cached) < 0 {
                            stabilized = -stabilized
                        }
                        lastRightAxis[id] = stabilized
                        return stabilized
                    }
                }
            }

            // Fallback: use cached axis or world-up.
            if let cached = lastRightAxis[id] {
                return cached
            }

            let worldUp = simd_float3(0, 1, 0)
            var right = simd_cross(worldUp, outward)
            if simd_length(right) < 0.0001 {
                right = simd_cross(simd_float3(1, 0, 0), outward)
            }
            let stabilized = simd_normalize(right)
            lastRightAxis[id] = stabilized
            return stabilized
        }


        /// Builds the base yaw/pitch/roll offsets as a quaternion.
        private func baseOrientationQuaternion(for config: SatelliteRenderConfig) -> simd_quatf {
            let yaw = simd_quatf(angle: config.baseYaw, axis: simd_float3(0, 1, 0))
            let pitch = simd_quatf(angle: config.basePitch, axis: simd_float3(1, 0, 0))
            let roll = simd_quatf(angle: config.baseRoll, axis: simd_float3(0, 0, 1))
            return yaw * pitch * roll
        }

        /// Walks up the node hierarchy to find the satellite id string.
        private func resolveSatelliteId(from node: SCNNode) -> Int? {
            var current: SCNNode? = node
            while let candidate = current {
                if let name = candidate.name, let id = Int(name) {
                    return id
                }
                current = candidate.parent
            }
            return nil
        }

        /// Applies a stable name to every node in the hierarchy for hit testing.
        private func applyName(_ name: String, to node: SCNNode) {
            node.name = name
            for child in node.childNodes {
                applyName(name, to: child)
            }
        }

        /// Applies a SceneKit category bitmask to the node hierarchy.
        private func applyCategory(_ mask: Int, to node: SCNNode) {
            node.categoryBitMask = mask
            for child in node.childNodes {
                applyCategory(mask, to: child)
            }
        }

        /// Clears cached nodes when the rendering mode changes.
        private func resetSatelliteNodes() {
            for node in satelliteNodes.values {
                node.removeFromParentNode()
            }
            satelliteNodes.removeAll()
            lastPositions.removeAll()
            lastOrientation.removeAll()
            lastRightAxis.removeAll()
            lastTickTimestamp = nil
            lastAnimationDuration = 0
            nodeDetailTiers.removeAll()
            nodeUsesModel.removeAll()
            lastScale = nil
        }

        /// Normalizes satellite materials for stable, opaque rendering near screen edges.
        private func tuneSatelliteMaterials(_ root: SCNNode) {
            let applyToMaterials: ([SCNMaterial]) -> Void = { materials in
                for material in materials {
                    let properties: [SCNMaterialProperty] = [
                        material.diffuse,
                        material.emission,
                        material.normal,
                        material.roughness,
                        material.metalness,
                        material.ambientOcclusion,
                        material.transparent
                    ]
                    for property in properties {
                        property.magnificationFilter = .linear
                        property.minificationFilter = .linear
                        property.mipFilter = .linear
                        property.maxAnisotropy = 16
                    }

                    material.blendMode = .replace
                    material.transparencyMode = .aOne
                    material.writesToDepthBuffer = true
                    material.readsFromDepthBuffer = true

                }
            }

            if let materials = root.geometry?.materials {
                applyToMaterials(materials)
            }

            root.enumerateChildNodes { node, _ in
                guard let materials = node.geometry?.materials else { return }
                applyToMaterials(materials)
            }
        }
    }

    /// Previews skip USDZ loading to avoid SceneKit/Metal crashes in the canvas.
    private static var isRunningInPreview: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return true
        }
        return Bundle.main.bundlePath.contains("Previews")
    }

    /// Detects when the globe is running in the iOS simulator runtime.
    private static var isRunningInSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Uses safer materials when the runtime is sensitive to USDZ texture formats.
    private static var shouldUseSafeMaterials: Bool {
        isRunningInSimulator
    }

    /// Replaces USDZ materials with simple colors to avoid preview texture crashes.
    private static func applyPreviewSafeMaterials(to rootNode: SCNNode, color: UIColor) {
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
