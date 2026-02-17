//
//  GlobeSceneCoordinator.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/6/26.
//

import QuartzCore
@preconcurrency import SceneKit
import UIKit
import simd

/// SceneKit coordinator that owns mutable render state for the globe.
///
/// `GlobeSceneView` stays focused on SwiftUI bridging, while this coordinator
/// handles node reuse, gesture interactions, camera focus transitions, and
/// asynchronous orbit-path construction.
final class GlobeSceneCoordinator: NSObject, UIGestureRecognizerDelegate {
    /// Identifies which model template a satellite is currently using.
    enum DetailTier {
        case high
        case low
    }

    /// Category mask used for satellite hit testing.
    let satelliteCategoryMask = GlobeSceneView.satelliteCategoryMask
    /// Category mask used for orbital path visuals.
    let orbitPathCategoryMask = GlobeSceneView.orbitPathCategoryMask
    /// Limits how many orbit paths build concurrently to keep the UI responsive.
    static let maxConcurrentOrbitPathBuilds = 2

    var satelliteNodes: [Int: SCNNode] = [:]
    var lastPositions: [Int: SCNVector3] = [:]
    /// Cached orientation quaternions to smooth per-tick updates.
    var lastOrientation: [Int: simd_quatf] = [:]
    /// Cached right-axis vectors to stabilize yaw when velocity is noisy.
    var lastRightAxis: [Int: simd_float3] = [:]
    /// Timestamp of the most recent tracking tick for interpolation.
    var lastTickTimestamp: Date?
    /// Cached animation duration for smooth position updates.
    var lastAnimationDuration: TimeInterval = 0
    /// Tracks which detail tier each satellite node is using.
    var nodeDetailTiers: [Int: DetailTier] = [:]
    /// High-detail template generated from the USDZ model.
    var satelliteHighTemplateNode: SCNNode?
    /// Low-detail template that reuses simplified materials.
    var satelliteLowTemplateNode: SCNNode?
    /// Last LOD distances applied to the high-detail geometry.
    var lastLodDistances: [Float] = []
    /// Tracks whether the USDZ templates are currently in use.
    var currentUseModel = false
    /// Tracks which nodes are currently using model geometry for scaling.
    var nodeUsesModel: [Int: Bool] = [:]
    /// Last scale applied to model nodes so we avoid redundant updates.
    var lastScale: Float?
    /// Remembers whether yaw-following was enabled last tick to reset caches.
    var lastYawFollowsOrbit: Bool?
    /// Cached orbital path nodes keyed by shared orbital signatures.
    var orbitPathNodes: [OrbitSignature: SCNNode] = [:]
    /// In-flight orbit path build tasks.
    var orbitPathTasks: [OrbitSignature: Task<[SIMD3<Float>], Never>] = [:]
    /// Remembers the last orbit path config to refresh when settings change.
    var lastOrbitPathConfig: OrbitPathConfig?
    /// Remembers the active sample count so we can rebuild when it changes.
    var lastOrbitPathSampleCount: Int?
    /// Latest Earth-rotation alignment applied to orbit path nodes.
    var lastOrbitRotation: simd_quatf?
    /// Coverage overlay nodes keyed by satellite id.
    var coverageNodes: [Int: SCNNode] = [:]
    /// Last quantized coverage angle key used by each satellite node.
    var coverageGeometryKeys: [Int: Int] = [:]
    /// Shared coverage geometries cached by quantized footprint angle.
    var coverageGeometryCache: [Int: SCNGeometry] = [:]
    /// Tracks the most recent camera focus request token.
    var lastFocusToken: UUID?
    /// Stores a focus request until the satellite node exists.
    var pendingFocusRequest: SatelliteFocusRequest?
    /// Satellite currently being auto-followed by the camera, if any.
    var autoFollowSatelliteId: Int?
    /// True while the camera should keep recentering on the followed satellite.
    var isAutoFollowEnabled = false
    /// Last target direction used for auto-follow, to avoid redundant camera actions.
    var lastAutoFollowDirection: simd_float3?
    /// True while the user is actively panning/pinching the camera.
    var isCameraInteractionActive = false
    /// Counts active gesture recognizers so follow remains paused until all touches end.
    var activeCameraInteractionCount = 0
    /// Defers follow camera re-acquire until the next follow tick after gestures end.
    ///
    /// Rebinding immediately inside gesture callbacks can race with SceneKit's
    /// camera controller and cause visible zoom snapback.
    var needsFollowCameraReacquire = false
    /// Drives continuous camera follow updates between tracking ticks.
    var cameraFollowDisplayLink: CADisplayLink?
    /// Last timestamp observed from the display link.
    var lastDisplayLinkTimestamp: CFTimeInterval?
    /// Scales selection zoom relative to the home camera distance.
    let selectionZoomMultiplier: Float = 0.7
    /// Nominal display-link frame delta used when no timing sample exists yet.
    let nominalFrameDelta: Float = 1.0 / 60.0
    /// Color used for selection accents.
    var selectionColor: UIColor = .systemOrange
    /// Node that highlights the selected satellite.
    var selectionIndicatorNode: SCNNode?
    /// Action key used to replace in-flight camera focus animations.
    let cameraFocusActionKey = "cameraFocusOrbit"
    /// Home camera position for double-tap reset (0,0 over Africa).
    let homeCameraPosition = SCNVector3(0, 0, 3)
    /// Latest tuning knobs from SwiftUI.
    var renderConfig: SatelliteRenderConfig
    let onSelect: (Int?) -> Void
    let onStats: ((GlobeRenderStats) -> Void)?
    weak var view: SCNView?
    weak var cameraNode: SCNNode?

    init(
        onSelect: @escaping (Int?) -> Void,
        onStats: ((GlobeRenderStats) -> Void)?,
        config: SatelliteRenderConfig
    ) {
        self.onSelect = onSelect
        self.onStats = onStats
        self.renderConfig = config
    }

}
