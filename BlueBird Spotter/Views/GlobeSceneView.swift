//
//  GlobeSceneView.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/21/25.
//

import SceneKit
import SwiftUI

/// Wraps an `SCNView` to display a textured Earth and orbiting satellites.
struct GlobeSceneView: UIViewRepresentable {
    /// Scene-space radius for Earth after normalization.
    private static let earthRadiusScene: Float = 1.0
    /// Rotate the model so the prime meridian faces +Z when needed.
    private static let earthPrimeMeridianRotation: Float = -.pi / 2
    /// Enables optional debug markers for orientation checks.
    private static let showDebugMarkers = true

    /// Latest tracked satellite positions to render.
    let trackedSatellites: [TrackedSatellite]
    /// Notifies SwiftUI when the user taps a satellite node.
    let onSelect: (Int?) -> Void

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
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
        context.coordinator.updateSatellites(trackedSatellites, in: scene)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    /// Builds the base SceneKit scene with Earth, camera, and lighting.
    private func makeScene() -> SCNScene {
        let scene = SCNScene()

        // Build a textured Earth sphere with a matching clouds layer.
        let earthNode = loadEarthNode(radiusScene: Self.earthRadiusScene)
        scene.rootNode.addChildNode(earthNode)

        if Self.showDebugMarkers {
            addDebugMarkers(to: scene, earthRadiusScene: Self.earthRadiusScene)
        }

        // Camera sits back far enough to see the full globe.
        let camera = SCNCamera()
        camera.zFar = 50
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
        let earthRootNode = SCNNode()
        earthRootNode.name = "earthRoot"

        guard let url = Bundle.main.url(forResource: "Earth", withExtension: "usdz"),
              let referenceNode = SCNReferenceNode(url: url) else {
            return earthRootNode
        }

        referenceNode.load()
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

    /// Coordinator stores satellite nodes to avoid re-creating geometry each tick.
    final class Coordinator: NSObject {
        private var satelliteNodes: [Int: SCNNode] = [:]
        private let onSelect: (Int?) -> Void
        weak var view: SCNView?

        init(onSelect: @escaping (Int?) -> Void) {
            self.onSelect = onSelect
        }

        /// Updates positions in place and removes nodes for missing satellites.
        func updateSatellites(_ tracked: [TrackedSatellite], in scene: SCNScene) {
            let ids = Set(tracked.map { $0.satellite.id })
            for (id, node) in satelliteNodes where !ids.contains(id) {
                node.removeFromParentNode()
                satelliteNodes[id] = nil
            }

            SCNTransaction.begin()
            SCNTransaction.disableActions = true

            for trackedSatellite in tracked {
                let id = trackedSatellite.satellite.id
                let node = satelliteNodes[id] ?? makeSatelliteNode(for: trackedSatellite, in: scene)
                let position = GlobeCoordinateConverter.scenePosition(
                    from: trackedSatellite.position,
                    earthRadiusScene: GlobeSceneView.earthRadiusScene
                )
                node.position = position
            }

            SCNTransaction.commit()
        }

        /// Handles taps by hit-testing SceneKit nodes.
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = view else { return }
            let point = gesture.location(in: view)
            let hits = view.hitTest(point, options: nil)
            guard let node = hits.first?.node, let name = node.name else {
                onSelect(nil)
                return
            }

            if let id = Int(name) {
                onSelect(id)
            } else {
                onSelect(nil)
            }
        }

        /// Creates a small sphere for the satellite and stores it for reuse.
        private func makeSatelliteNode(for tracked: TrackedSatellite, in scene: SCNScene) -> SCNNode {
            let geometry = SCNSphere(radius: 0.015)
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.systemYellow
            geometry.materials = [material]

            let node = SCNNode(geometry: geometry)
            node.name = String(tracked.satellite.id)
            scene.rootNode.addChildNode(node)
            satelliteNodes[tracked.satellite.id] = node
            return node
        }
    }
}
