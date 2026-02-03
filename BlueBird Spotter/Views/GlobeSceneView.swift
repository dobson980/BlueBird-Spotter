//
//  GlobeSceneView.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/21/25.
//

import SceneKit
import SwiftUI
import simd

/// Wraps an `SCNView` to display Earth and orbiting satellites.
struct GlobeSceneView: UIViewRepresentable {
    /// Scene-space radius for Earth after normalization.
    private static let earthRadiusScene: Float = 1.0
    /// Rotate the model so the prime meridian faces +Z when needed.
    private static let earthPrimeMeridianRotation: Float = -.pi / 2
    /// Enables optional debug markers for orientation checks.
    private static let showDebugMarkers = GlobeDebugFlags.showDebugMarkers

    /// Latest tracked satellite positions to render.
    let trackedSatellites: [TrackedSatellite]
    /// Render controls supplied by SwiftUI.
    let config: SatelliteRenderConfig
    /// Notifies SwiftUI when the user taps a satellite node.
    let onSelect: (Int?) -> Void

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.antialiasingMode = .multisampling4X
        view.scene = makeScene()
        view.backgroundColor = UIColor.systemBackground
        view.allowsCameraControl = true
        view.cameraControlConfiguration.allowsTranslation = false
        view.autoenablesDefaultLighting = false

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.view = view

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let scene = uiView.scene else { return }
        context.coordinator.renderConfig = config
        context.coordinator.updateSatellites(trackedSatellites, in: scene)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, config: config)
    }

    /// Builds the base SceneKit scene with Earth, camera, and lighting.
    private func makeScene() -> SCNScene {
        let scene = SCNScene()

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
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 3)
        scene.rootNode.addChildNode(cameraNode)

        // Lighting keeps the day/night contrast while letting night lights read.
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 900
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowRadius = 6
        sun.shadowColor = UIColor.black.withAlphaComponent(0.6)
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.6, 0.3, 0)
        scene.rootNode.addChildNode(sunNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 40
        let ambientNode = SCNNode()
        ambientNode.light = ambient
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
                altitudeKm: 0
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
    final class Coordinator: NSObject {
        private var satelliteNodes: [Int: SCNNode] = [:]
        private var lastPositions: [Int: SCNVector3] = [:]
        private var satelliteTemplateNode: SCNNode?
        private var currentUseModel = false
        /// Latest tuning knobs from SwiftUI.
        var renderConfig: SatelliteRenderConfig
        private let onSelect: (Int?) -> Void
        weak var view: SCNView?

        init(onSelect: @escaping (Int?) -> Void, config: SatelliteRenderConfig) {
            self.onSelect = onSelect
            self.renderConfig = config
        }

        /// Updates positions in place and removes nodes for missing satellites.
        func updateSatellites(_ tracked: [TrackedSatellite], in scene: SCNScene) {
            let shouldUseModel = renderConfig.useModel && !GlobeSceneView.isRunningInPreview
            if shouldUseModel != currentUseModel {
                resetSatelliteNodes()
                currentUseModel = shouldUseModel
            }

            let ids = Set(tracked.map { $0.satellite.id })
            for (id, node) in satelliteNodes where !ids.contains(id) {
                node.removeFromParentNode()
                satelliteNodes[id] = nil
                lastPositions[id] = nil
            }

            SCNTransaction.begin()
            SCNTransaction.disableActions = true

            for trackedSatellite in tracked {
                let id = trackedSatellite.satellite.id
                let node = satelliteNodes[id] ?? makeSatelliteNode(
                    for: trackedSatellite,
                    in: scene,
                    allowModel: shouldUseModel
                )
                let position = GlobeCoordinateConverter.scenePosition(
                    from: trackedSatellite.position,
                    earthRadiusScene: GlobeSceneView.earthRadiusScene
                )
                node.position = position
                applyOrientation(for: id, node: node, currentPosition: position)

                if shouldUseModel {
                    let scale = renderConfig.scale
                    node.scale = SCNVector3(scale, scale, scale)
                }
            }

            SCNTransaction.commit()
        }

        /// Handles taps by hit-testing SceneKit nodes.
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = view else { return }
            let point = gesture.location(in: view)
            let hits = view.hitTest(point, options: nil)
            guard let hitNode = hits.first?.node else {
                onSelect(nil)
                return
            }

            onSelect(resolveSatelliteId(from: hitNode))
        }

        /// Creates a satellite node, using USDZ when available and storing it for reuse.
        private func makeSatelliteNode(
            for tracked: TrackedSatellite,
            in scene: SCNScene,
            allowModel: Bool
        ) -> SCNNode {
            let node: SCNNode
            if allowModel, let modelNode = loadSatelliteTemplate()?.clone() {
                node = modelNode
            } else {
                let geometry = SCNSphere(radius: 0.015)
                let material = SCNMaterial()
                material.diffuse.contents = UIColor.systemYellow
                geometry.materials = [material]
                node = SCNNode(geometry: geometry)
            }

            let name = String(tracked.satellite.id)
            applyName(name, to: node)

            scene.rootNode.addChildNode(node)
            satelliteNodes[tracked.satellite.id] = node
            return node
        }

        /// Loads and caches the USDZ satellite template for cloning.
        private func loadSatelliteTemplate() -> SCNNode? {
            if let cached = satelliteTemplateNode {
                return cached
            }
            guard let url = Bundle.main.url(forResource: "BlueBird", withExtension: "usdz"),
                  let referenceNode = SCNReferenceNode(url: url) else {
                return nil
            }
            referenceNode.load()
            tuneSatelliteMaterials(referenceNode)
            if GlobeSceneView.shouldUseSafeMaterials {
                // Simulators use flat materials to avoid USDZ texture format issues.
                GlobeSceneView.applyPreviewSafeMaterials(to: referenceNode, color: .systemYellow)
            }

            let container = SCNNode()
            container.addChildNode(referenceNode)

            // Center the pivot so rotations happen around the model's center of mass.
            let (minBounds, maxBounds) = referenceNode.boundingBox
            let center = SCNVector3(
                (minBounds.x + maxBounds.x) * 0.5,
                (minBounds.y + maxBounds.y) * 0.5,
                (minBounds.z + maxBounds.z) * 0.5
            )
            // SceneKit pivots are applied before transforms, so negate to move the center to origin.
            container.pivot = SCNMatrix4MakeTranslation(-center.x, -center.y, -center.z)

            satelliteTemplateNode = container
            return container
        }

        /// Computes orientation so the model points toward Earth and optionally along velocity.
        private func applyOrientation(for id: Int, node: SCNNode, currentPosition: SCNVector3) {
            defer { lastPositions[id] = currentPosition }

            let config = renderConfig
            let baseOffset = baseOrientationQuaternion(for: config)
            guard config.nadirPointing else {
                node.simdOrientation = baseOffset
                return
            }

            let position = currentPosition.simd
            let distance = simd_length(position)
            guard distance > 0 else {
                node.simdOrientation = baseOffset
                return
            }

            // Model forward is assumed to be -Z, so +Z points away from Earth.
            let outward = position / distance
            let radial = -outward
            let right = preferredRightAxis(
                for: id,
                radial: radial,
                outward: outward,
                currentPosition: currentPosition
            )
            let up = simd_normalize(simd_cross(outward, right))

            let basis = simd_float3x3(columns: (right, up, outward))
            let orientation = simd_quatf(basis)

            // Apply base offsets after attitude so artists can correct model alignment.
            node.simdOrientation = orientation * baseOffset
        }

        /// Picks a stable right axis, favoring velocity tangent when enabled.
        private func preferredRightAxis(
            for id: Int,
            radial: simd_float3,
            outward: simd_float3,
            currentPosition: SCNVector3
        ) -> simd_float3 {
            if renderConfig.yawFollowsOrbit,
               let previous = lastPositions[id] {
                let velocity = (currentPosition - previous).simd
                let velocityLength = simd_length(velocity)
                if velocityLength > 0 {
                    let velocityDir = velocity / velocityLength
                    let projected = velocityDir - radial * simd_dot(velocityDir, radial)
                    if simd_length(projected) > 0.0001 {
                        return simd_normalize(projected)
                    }
                }
            }

            let worldUp = simd_float3(0, 1, 0)
            var right = simd_cross(worldUp, outward)
            if simd_length(right) < 0.0001 {
                right = simd_cross(simd_float3(1, 0, 0), outward)
            }
            return simd_normalize(right)
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

        /// Clears cached nodes when the rendering mode changes.
        private func resetSatelliteNodes() {
            for node in satelliteNodes.values {
                node.removeFromParentNode()
            }
            satelliteNodes.removeAll()
            lastPositions.removeAll()
            satelliteTemplateNode = nil
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
