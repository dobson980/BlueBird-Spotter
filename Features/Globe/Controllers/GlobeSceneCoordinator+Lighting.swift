//
//  GlobeSceneCoordinator+Lighting.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/18/26.
//

import Foundation
import SceneKit

/// Lighting updates for the globe scene.
///
/// Why this exists:
/// - Lighting behavior is independent from camera transitions and gestures.
/// - Isolating this logic keeps camera files focused on interaction behavior.
///
/// What this does NOT do:
/// - It does not manage satellite nodes or camera state.
extension GlobeSceneCoordinator {
    /// Updates directional and ambient lighting based on user settings and UTC time.
    func updateLighting(
        in scene: SCNScene,
        isDirectionalLightEnabled: Bool,
        at date: Date
    ) {
        let sunNode = scene.rootNode.childNode(withName: "sunLight", recursively: false)
        let ambientNode = scene.rootNode.childNode(withName: "ambientLight", recursively: false)
        if let sunNode {
            updateSunNodeDirection(sunNode, at: date)
        }

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

    /// Orients the directional light using the real-time subsolar point.
    private func updateSunNodeDirection(_ sunNode: SCNNode, at date: Date) {
        let directionToSun = SolarLightingModel.sceneSunDirection(at: date)
        let sunPosition = directionToSun * GlobeSceneView.sunLightNodeDistance
        sunNode.position = SCNVector3(sunPosition.x, sunPosition.y, sunPosition.z)
        // Looking at Earth's center aligns the light ray direction with incoming sunlight.
        sunNode.look(at: SCNVector3Zero)
    }
}
