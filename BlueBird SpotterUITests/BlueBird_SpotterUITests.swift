//
//  BlueBird_SpotterUITests.swift
//  BlueBird SpotterUITests
//
//  Created by Tom Dobson on 12/19/25.
//

import XCTest

/// Basic UI smoke tests that exercise app launch behavior.
final class BlueBird_SpotterUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {}

    /// Launches the app to confirm it starts without crashing.
    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launch()
    }

    /// Measures launch performance for regression awareness.
    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
