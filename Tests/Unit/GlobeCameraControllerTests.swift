//
//  GlobeCameraControllerTests.swift
//  BlueBird SpotterTests
//
//  Created by Tom Dobson on 2/18/26.
//

import Foundation
import SceneKit
import Testing
@testable import BlueBird_Spotter

/// Unit tests for deterministic globe camera state-machine behavior.
///
/// Why this exists:
/// - Camera transitions and follow rules are interaction-heavy and easy to regress.
/// - These tests validate camera decisions without relying on UI test gestures.
///
/// What this does NOT do:
/// - It does not verify rendered pixels or SceneKit lighting output.
struct GlobeCameraControllerTests {
    /// Mutable satellite direction store shared with the controller's provider closure.
    @MainActor
    private final class DirectionStore {
        var directions: [Int: simd_float3] = [:]
    }

    /// Builds a camera controller fixture with a deterministic home pose.
    @MainActor
    private func makeControllerFixture() -> (
        controller: GlobeCameraController,
        store: DirectionStore,
        homeDirection: simd_float3,
        cameraNode: SCNNode
    ) {
        let cameraNode = SCNNode()
        cameraNode.position = SCNVector3(0, 0, 3)

        let controller = GlobeCameraController(
            homeCameraPosition: SCNVector3(0, 0, 3),
            selectionZoomMultiplier: 0.7,
            minimumFollowDistance: 1.02,
            maximumFollowDistance: 11,
            maxPitchRadians: 85 * .pi / 180
        )
        controller.attachCameraNode(cameraNode)

        let store = DirectionStore()
        controller.satelliteDirectionProvider = { satelliteId in
            store.directions[satelliteId]
        }

        return (controller, store, simd_float3(0, 0, 1), cameraNode)
    }

    /// Advances the camera pipeline for a fixed number of 60 FPS frames.
    @MainActor
    private func advanceFrames(_ frameCount: Int, for controller: GlobeCameraController) {
        for _ in 0..<frameCount {
            controller.tick(frameDelta: 1.0 / 60.0)
        }
    }

    /// Returns true when scalar values are approximately equal.
    private func approximatelyEqual(_ lhs: Float, _ rhs: Float, tolerance: Float = 0.01) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    /// Returns true when two direction vectors are nearly aligned.
    private func nearlyAligned(_ lhs: simd_float3, _ rhs: simd_float3, minimumDot: Float = 0.999) -> Bool {
        simd_dot(lhs, rhs) >= minimumDot
    }

    /// Focus request should orbit first, then zoom, then enter follow mode.
    @Test @MainActor func selectSatellite_firstTime_orbitsThenZooms_thenFollows() {
        let fixture = makeControllerFixture()
        fixture.store.directions[1] = simd_normalize(simd_float3(1, 0, 0.2))

        let accepted = fixture.controller.requestFocus(satelliteId: 1, token: UUID())
        #expect(accepted)
        #expect(fixture.controller.mode == .transitioning(toSatelliteId: 1))

        advanceFrames(200, for: fixture.controller)

        #expect(fixture.controller.mode == .following(satelliteId: 1))
        #expect(approximatelyEqual(fixture.controller.distance, 2.1, tolerance: 0.05))
        #expect(nearlyAligned(fixture.controller.state.direction, fixture.store.directions[1] ?? simd_float3(0, 0, 1), minimumDot: 0.995))
    }

    /// Focus transitions should begin zooming before the final tail of the timeline.
    @Test @MainActor func focusTransition_standardZoomDelta_startsZoomEarlierThanLegacyPhase() {
        let fixture = makeControllerFixture()
        // Same direction isolates zoom timing from orbital rotation so this test
        // only validates transition pacing changes.
        fixture.store.directions[77] = simd_float3(0, 0, 1)

        let accepted = fixture.controller.requestFocus(satelliteId: 77, token: UUID())
        #expect(accepted)
        guard let transition = fixture.controller.state.transition else {
            #expect(Bool(false), "Expected a focus transition to start.")
            return
        }

        #expect(transition.rotationPhase < 0.85)
        #expect(transition.duration > 1.45)
    }

    /// Pinch zoom during follow should persist instead of snapping back to entry zoom.
    @Test @MainActor func following_pinchChangesDistance_distancePersistsAcrossTicks() {
        let fixture = makeControllerFixture()
        fixture.store.directions[1] = simd_normalize(simd_float3(0.4, 0.2, 1))
        _ = fixture.controller.requestFocus(satelliteId: 1, token: UUID())
        advanceFrames(200, for: fixture.controller)
        #expect(fixture.controller.mode == .following(satelliteId: 1))

        fixture.controller.beginPinch()
        fixture.controller.updatePinch(scale: 0.5)
        fixture.controller.endPinch()
        let userDistance = fixture.controller.distance

        fixture.store.directions[1] = simd_normalize(simd_float3(0.7, 0.1, 0.6))
        advanceFrames(120, for: fixture.controller)

        #expect(fixture.controller.mode == .following(satelliteId: 1))
        #expect(approximatelyEqual(fixture.controller.distance, userDistance, tolerance: 0.02))
    }

    /// Selecting a second satellite after deselect should start from current pose with no zoom snap.
    @Test @MainActor func deselect_thenSelectAnother_startsFromCurrentPose_noZoomSnap() {
        let fixture = makeControllerFixture()
        fixture.store.directions[1] = simd_normalize(simd_float3(0.8, 0.1, 0.4))
        fixture.store.directions[2] = simd_normalize(simd_float3(-0.7, 0.1, 0.6))

        _ = fixture.controller.requestFocus(satelliteId: 1, token: UUID())
        advanceFrames(180, for: fixture.controller)
        fixture.controller.beginPinch()
        fixture.controller.updatePinch(scale: 0.35)
        fixture.controller.endPinch()

        fixture.controller.clearSelection()
        let startDistance = fixture.controller.distance

        _ = fixture.controller.requestFocus(satelliteId: 2, token: UUID())
        advanceFrames(1, for: fixture.controller)

        #expect(approximatelyEqual(fixture.controller.distance, startDistance, tolerance: 0.03))
    }

    /// Dragging past the threshold while following should deselect and stop follow mode.
    @Test @MainActor func panBeyondThreshold_whileFollowing_deselectsAndStopsFollow() {
        let fixture = makeControllerFixture()
        fixture.store.directions[1] = simd_normalize(simd_float3(0.2, 0.3, 0.9))
        _ = fixture.controller.requestFocus(satelliteId: 1, token: UUID())
        advanceFrames(180, for: fixture.controller)
        #expect(fixture.controller.mode == .following(satelliteId: 1))

        fixture.controller.beginPan()
        let didDeselect = fixture.controller.updatePan(
            delta: CGPoint(x: 25, y: 0),
            totalTranslation: CGPoint(x: 25, y: 0),
            deselectThreshold: 15
        )
        fixture.controller.endPan()

        #expect(didDeselect)
        #expect(fixture.controller.mode == .freeOrbit)
        #expect(fixture.controller.state.selectedSatelliteId == nil)
    }

    /// Home reset should clear selection and return to the home pose from any mode.
    @Test @MainActor func doubleTap_fromAnyMode_resetsToHome_andClearsSelection() {
        let fixture = makeControllerFixture()
        fixture.store.directions[1] = simd_normalize(simd_float3(0.9, 0.1, 0.2))
        _ = fixture.controller.requestFocus(satelliteId: 1, token: UUID())
        advanceFrames(180, for: fixture.controller)

        fixture.controller.requestResetHome()
        #expect(fixture.controller.mode == .resettingHome)
        #expect(fixture.controller.state.selectedSatelliteId == nil)

        advanceFrames(220, for: fixture.controller)

        #expect(fixture.controller.mode == .freeOrbit)
        #expect(approximatelyEqual(fixture.controller.distance, 3, tolerance: 0.05))
        #expect(nearlyAligned(fixture.controller.state.direction, fixture.homeDirection, minimumDot: 0.999))
    }

    /// New focus during transition should restart from the current interpolated pose.
    @Test @MainActor func newFocusDuringTransition_cancelsPrior_andStartsFromCurrentInterpolatedPose() {
        let fixture = makeControllerFixture()
        fixture.store.directions[1] = simd_normalize(simd_float3(0.9, 0, 0.1))
        fixture.store.directions[2] = simd_normalize(simd_float3(-0.8, 0, 0.2))

        let firstToken = UUID()
        let secondToken = UUID()
        _ = fixture.controller.requestFocus(satelliteId: 1, token: firstToken)
        advanceFrames(25, for: fixture.controller)
        let intermediateDirection = fixture.controller.state.direction
        let intermediateDistance = fixture.controller.distance

        let accepted = fixture.controller.requestFocus(satelliteId: 2, token: secondToken)
        #expect(accepted)
        #expect(fixture.controller.mode == .transitioning(toSatelliteId: 2))
        #expect(fixture.controller.state.transition?.satelliteId == 2)
        #expect(approximatelyEqual(fixture.controller.state.transition?.startDistance ?? 0, intermediateDistance, tolerance: 0.02))
        #expect(nearlyAligned(fixture.controller.state.transition?.startDirection ?? simd_float3(0, 0, 1), intermediateDirection, minimumDot: 0.998))
    }

    /// A new token for the same satellite should restart transition, while duplicate token should not.
    @Test @MainActor func focusRequestSameSatelliteNewToken_restartsTransition() {
        let fixture = makeControllerFixture()
        fixture.store.directions[7] = simd_normalize(simd_float3(0.5, 0.1, 0.8))
        let tokenA = UUID()
        let tokenB = UUID()

        #expect(fixture.controller.requestFocus(satelliteId: 7, token: tokenA))
        advanceFrames(20, for: fixture.controller)
        let previousElapsed = fixture.controller.state.transition?.elapsed ?? 0

        #expect(!fixture.controller.requestFocus(satelliteId: 7, token: tokenA))
        #expect(fixture.controller.requestFocus(satelliteId: 7, token: tokenB))
        #expect((fixture.controller.state.transition?.elapsed ?? 0) < previousElapsed)
        #expect(fixture.controller.state.lastFocusToken == tokenB)
    }

    /// Distance should remain in configured bounds through pinch and follow updates.
    @Test @MainActor func distanceClamping_respectsBounds_withoutSnapArtifacts() {
        let fixture = makeControllerFixture()
        fixture.store.directions[3] = simd_normalize(simd_float3(0.2, 0.2, 0.9))
        _ = fixture.controller.requestFocus(satelliteId: 3, token: UUID())
        advanceFrames(180, for: fixture.controller)

        fixture.controller.beginPinch()
        var pinchInScale: CGFloat = 1
        for _ in 0..<14 {
            pinchInScale *= 1.65
            fixture.controller.updatePinch(scale: pinchInScale)
        }
        fixture.controller.endPinch()
        #expect(approximatelyEqual(fixture.controller.distance, 1.02, tolerance: 0.05))

        fixture.controller.beginPinch()
        var pinchOutScale: CGFloat = 1
        for _ in 0..<24 {
            pinchOutScale *= 0.6
            fixture.controller.updatePinch(scale: pinchOutScale)
        }
        fixture.controller.endPinch()
        #expect(approximatelyEqual(fixture.controller.distance, 11.0, tolerance: 0.05))

        fixture.store.directions[3] = simd_normalize(simd_float3(-0.4, 0.3, 0.85))
        advanceFrames(120, for: fixture.controller)
        #expect(approximatelyEqual(fixture.controller.distance, 11.0, tolerance: 0.05))
        #expect(fixture.controller.distance >= 1.02)
        #expect(fixture.controller.distance <= 11.0)
    }

    /// Camera orientation should keep a positive world-up component to avoid upside-down roll.
    @Test @MainActor func cameraOrientation_neverRollsUpsideDown_duringFollow() {
        let fixture = makeControllerFixture()
        fixture.store.directions[9] = simd_normalize(simd_float3(0.2, -0.95, 0.25))

        _ = fixture.controller.requestFocus(satelliteId: 9, token: UUID())
        advanceFrames(220, for: fixture.controller)

        let firstUp = simd_float3(
            fixture.cameraNode.simdTransform.columns.1.x,
            fixture.cameraNode.simdTransform.columns.1.y,
            fixture.cameraNode.simdTransform.columns.1.z
        )
        #expect(firstUp.y > 0.001)

        fixture.store.directions[9] = simd_normalize(simd_float3(-0.55, 0.8, -0.22))
        advanceFrames(200, for: fixture.controller)

        let secondUp = simd_float3(
            fixture.cameraNode.simdTransform.columns.1.x,
            fixture.cameraNode.simdTransform.columns.1.y,
            fixture.cameraNode.simdTransform.columns.1.z
        )
        #expect(secondUp.y > 0.001)
    }

    /// Reattaching the same camera node should not overwrite user pinch distance.
    @Test @MainActor func attachSameCameraNode_preservesPinchDistanceDuringFollow() {
        let fixture = makeControllerFixture()
        fixture.store.directions[11] = simd_normalize(simd_float3(0.45, 0.15, 0.88))

        _ = fixture.controller.requestFocus(satelliteId: 11, token: UUID())
        advanceFrames(200, for: fixture.controller)
        #expect(fixture.controller.mode == .following(satelliteId: 11))

        fixture.controller.beginPinch()
        fixture.controller.updatePinch(scale: 0.55)
        fixture.controller.endPinch()
        let userDistance = fixture.controller.distance

        // Coordinator may call ensure/attach repeatedly during follow ticks.
        for _ in 0..<120 {
            fixture.controller.attachCameraNode(fixture.cameraNode)
            fixture.controller.tick(frameDelta: 1.0 / 60.0)
        }

        #expect(approximatelyEqual(fixture.controller.distance, userDistance, tolerance: 0.02))
    }
}
