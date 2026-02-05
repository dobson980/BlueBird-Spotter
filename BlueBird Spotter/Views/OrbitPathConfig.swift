//
//  OrbitPathConfig.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/3/26.
//

import UIKit

/// Defines how orbital paths are sampled and rendered in SceneKit.
struct OrbitPathConfig: Equatable {
    /// Number of samples taken along a full orbital period.
    let sampleCount: Int
    /// Offset that pulls the path slightly toward Earth to avoid clipping the satellite.
    let altitudeOffsetKm: Double
    /// Base color for the path material.
    let lineColor: UIColor
    /// Opacity for the path material.
    let lineOpacity: CGFloat
    /// World-space thickness for the orbit path ribbon.
    let lineWidth: CGFloat

    /// Default path styling tuned for visibility without overpowering the globe.
    static let `default` = OrbitPathConfig(
        sampleCount: 180,
        altitudeOffsetKm: 15,
        lineColor: UIColor(red: 1.0, green: 0.47, blue: 0.0, alpha: 1.0),
        lineOpacity: 0.55,
        lineWidth: 0.003
    )
}
