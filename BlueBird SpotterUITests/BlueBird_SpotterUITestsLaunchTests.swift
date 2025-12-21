//
//  BlueBird_SpotterUITestsLaunchTests.swift
//  BlueBird SpotterUITests
//
//  Created by Tom Dobson on 12/19/25.
//

import XCTest

/// Captures a launch snapshot for visual regression checks.
final class BlueBird_SpotterUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Takes a screenshot right after launch for reference.
    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
