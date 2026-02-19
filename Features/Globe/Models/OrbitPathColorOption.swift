//
//  OrbitPathColorOption.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/6/26.
//

import SwiftUI
import UIKit

/// Defines one selectable color option for orbit path rendering.
///
/// This type is separated from `GlobeView` so color palette policy lives in one
/// focused place and UI files stay easier to scan.
struct OrbitPathColorOption: Identifiable, Hashable {
    let id: String
    let name: String
    let uiColor: UIColor

    var color: Color { Color(uiColor: uiColor) }

    // ASTS orange is the default to match the brand accent.
    private static let astsOrange = OrbitPathColorOption(
        id: "astsOrange",
        name: "ASTS Orange",
        uiColor: UIColor(red: 1.0, green: 0.47, blue: 0.0, alpha: 1.0)
    )

    static let options: [OrbitPathColorOption] = [
        astsOrange,
        OrbitPathColorOption(
            id: "solarYellow",
            name: "Solar Yellow",
            uiColor: UIColor(red: 1.0, green: 0.84, blue: 0.2, alpha: 1.0)
        ),
        OrbitPathColorOption(
            id: "magenta",
            name: "Magenta",
            uiColor: UIColor(red: 0.92, green: 0.2, blue: 0.92, alpha: 1.0)
        ),
        OrbitPathColorOption(
            id: "electricBlue",
            name: "Electric Blue",
            uiColor: UIColor(red: 0.25, green: 0.6, blue: 1.0, alpha: 1.0)
        ),
        OrbitPathColorOption(
            id: "lime",
            name: "Lime",
            uiColor: UIColor(red: 0.55, green: 1.0, blue: 0.3, alpha: 1.0)
        )
    ]

    static let defaultOption = astsOrange
    static let defaultId = astsOrange.id
}
