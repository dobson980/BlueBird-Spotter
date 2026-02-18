//
//  GlobeSceneCoordinator+CameraGestures.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/18/26.
//

import SceneKit
import UIKit

/// Gesture routing for the custom globe camera controller.
///
/// Why this exists:
/// - SceneKit's built-in camera control is disabled, so gestures must explicitly
///   map into the camera state machine.
/// - Keeping gesture code separate from pipeline/lighting makes behavior easier to audit.
///
/// What this does NOT do:
/// - It does not implement camera interpolation math.
///   `GlobeCameraController` owns transition/follow interpolation.
extension GlobeSceneCoordinator {
    /// Handles taps by hit-testing satellite nodes and issuing unified focus requests.
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = view else { return }
        let point = gesture.location(in: view)
        let hits = view.hitTest(point, options: [
            SCNHitTestOption.categoryBitMask: satelliteCategoryMask
        ])

        guard let selectedHit = hits.first(where: { !isSelectionIndicatorNode($0.node) }),
              let satelliteId = resolveSatelliteId(from: selectedHit.node) else {
            disableAutoFollow()
            onSelect(nil)
            return
        }

        requestFocus(satelliteId: satelliteId, token: UUID(), in: view.scene)
        onSelect(satelliteId)
    }

    /// Resets the camera to the home position and clears selection on double-tap.
    @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let scene = view?.scene else { return }
        _ = ensureCameraController(in: scene)

        pendingFocusRequest = nil
        cameraController?.requestResetHome()
        onSelect(nil)
        updateDisplayLinkPauseState()
    }

    /// Routes one-finger drag gestures into custom orbit camera updates.
    @objc func handlePanInteraction(_ gesture: UIPanGestureRecognizer) {
        if let scene = view?.scene {
            _ = ensureCameraController(in: scene)
        }

        switch gesture.state {
        case .began:
            // Ignore pan ownership while pinch is active.
            guard !isPinchGestureActive, gesture.numberOfTouches == 1 else { return }
            isPanGestureActive = true
            lastPanTranslation = .zero
            cameraController?.beginPan()
            refreshInteractionState()
        case .changed:
            guard isPanGestureActive, !isPinchGestureActive, gesture.numberOfTouches == 1 else { return }
            let translation = gesture.translation(in: view)
            let delta = CGPoint(
                x: translation.x - lastPanTranslation.x,
                y: translation.y - lastPanTranslation.y
            )
            lastPanTranslation = translation
            let didDeselect = cameraController?.updatePan(
                delta: delta,
                totalTranslation: translation,
                deselectThreshold: 15
            ) ?? false
            if didDeselect {
                pendingFocusRequest = nil
                onSelect(nil)
            }
        case .ended, .cancelled, .failed:
            lastPanTranslation = .zero
            if isPanGestureActive {
                cameraController?.endPan()
            }
            isPanGestureActive = false
            refreshInteractionState()
        default:
            break
        }
    }

    /// Routes pinch gestures into custom camera-distance updates.
    @objc func handlePinchInteraction(_ gesture: UIPinchGestureRecognizer) {
        if let scene = view?.scene {
            _ = ensureCameraController(in: scene)
        }

        switch gesture.state {
        case .began:
            isPinchGestureActive = true
            // Pinch always takes precedence over pan ownership.
            if isPanGestureActive {
                isPanGestureActive = false
                lastPanTranslation = .zero
                cameraController?.endPan()
            }
            cameraController?.beginPinch()
            refreshInteractionState()
        case .changed:
            guard isPinchGestureActive else { return }
            cameraController?.updatePinch(scale: gesture.scale)
        case .ended, .cancelled, .failed:
            if isPinchGestureActive {
                cameraController?.endPinch()
            }
            isPinchGestureActive = false
            refreshInteractionState()
        default:
            break
        }
    }

    /// Synchronizes gesture ownership flags with shared camera interaction state.
    private func refreshInteractionState() {
        isCameraInteractionActive = isPanGestureActive || isPinchGestureActive
        if !isCameraInteractionActive {
            processPendingFocusIfPossible()
        }
        updateDisplayLinkPauseState()
    }

    /// Ignores the visual selection halo during hit-testing so taps target satellites only.
    private func isSelectionIndicatorNode(_ node: SCNNode) -> Bool {
        guard let indicator = selectionIndicatorNode else { return false }
        var current: SCNNode? = node
        while let candidate = current {
            if candidate === indicator {
                return true
            }
            current = candidate.parent
        }
        return false
    }

    /// Allows recognizers to run together so pan/pinch interaction remains fluid.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    /// Prevents SceneKit-internal recognizers from blocking our custom gestures.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
