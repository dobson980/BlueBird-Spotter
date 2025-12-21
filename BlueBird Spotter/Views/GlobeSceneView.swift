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

        // Earth sphere sized so radius = 1 SceneKit unit.
        let earthGeometry = SCNSphere(radius: 1.0)
        let earthMaterial = SCNMaterial()
        earthMaterial.diffuse.contents = UIImage(named: "EarthTexture")
        earthMaterial.specular.contents = UIColor.white.withAlphaComponent(0.2)
        earthGeometry.materials = [earthMaterial]

        let earthNode = SCNNode(geometry: earthGeometry)
        scene.rootNode.addChildNode(earthNode)

        // Camera sits back far enough to see the full globe.
        let camera = SCNCamera()
        camera.zFar = 50
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 3)
        scene.rootNode.addChildNode(cameraNode)

        // Lighting keeps the sphere readable while still showing texture detail.
        let light = SCNLight()
        light.type = .omni
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.position = SCNVector3(2, 2, 4)
        scene.rootNode.addChildNode(lightNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 350
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        return scene
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
                    latitudeDegrees: trackedSatellite.position.latitudeDegrees,
                    longitudeDegrees: trackedSatellite.position.longitudeDegrees,
                    altitudeKm: trackedSatellite.position.altitudeKm
                )
                node.position = SCNVector3(position.x, position.y, position.z)
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
