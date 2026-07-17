//
//  MacFlowInteractionTests.swift
//  MacFlowUITests
//
//  Regression coverage for the real AppKit/SwiftUI click paths that model
//  tests cannot exercise.
//

import XCTest

final class MacFlowInteractionTests: XCTestCase {
    private var app: XCUIApplication!
    private var sceneRoot: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false

        sceneRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacFlow-UITests-\(UUID().uuidString)", isDirectory: true)

        app = XCUIApplication()
        app.launchEnvironment["MACFLOW_UI_TESTING"] = "1"
        app.launchEnvironment["MACFLOW_UI_TEST_SCENE_ROOT"] = sceneRoot.path
        app.launch()

        XCTAssertTrue(
            app.windows["MacFlow"].waitForExistence(timeout: 5),
            "The isolated MacFlow companion window should open for UI testing."
        )
    }

    override func tearDownWithError() throws {
        app?.terminate()
        if let sceneRoot {
            try? FileManager.default.removeItem(at: sceneRoot)
        }
        app = nil
        sceneRoot = nil
    }

    func testWallpaperToolbarSurvivesRapidLayoutAndMenuChanges() {
        navigate(to: "sidebar.wallpaperEngine")

        let grid = element("wallpapers.layout.grid")
        let list = element("wallpapers.layout.list")
        let sort = element("wallpapers.sort")
        let options = element("wallpapers.options")
        let importButton = element("wallpapers.import")

        for control in [grid, list, sort, options, importButton] {
            XCTAssertTrue(control.waitForExistence(timeout: 3))
            XCTAssertTrue(control.isHittable)
        }

        for _ in 0..<6 {
            list.click()
            grid.click()
        }
        XCTAssertEqual(grid.value as? String, "Selected")
        XCTAssertEqual(list.value as? String, "Not selected")

        sort.click()
        XCTAssertTrue(sort.exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(sort.exists)

        options.click()
        XCTAssertTrue(options.exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(options.exists)

        importButton.click()
        XCTAssertNotEqual(app.state, .notRunning)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.windows["MacFlow"].waitForExistence(timeout: 3))
    }

    func testAppearanceAndFocusMonitorRoutesRemainInteractive() {
        navigate(to: "sidebar.notch")

        let appearance = element("notch.tab.appearance")
        XCTAssertTrue(appearance.waitForExistence(timeout: 3))
        appearance.click()
        XCTAssertTrue(element("notch.appearance.form").waitForExistence(timeout: 3))
        XCTAssertNotEqual(app.state, .notRunning)

        navigate(to: "sidebar.preferences")
        let setup = element("preferences.section.setup")
        XCTAssertTrue(setup.waitForExistence(timeout: 3))
        setup.click()

        let focusMonitor = element("preferences.focusMonitor")
        XCTAssertTrue(focusMonitor.waitForExistence(timeout: 3))
        XCTAssertTrue(focusMonitor.isHittable)

        let initialValue = String(describing: focusMonitor.value)
        focusMonitor.click()
        XCTAssertNotEqual(String(describing: focusMonitor.value), initialValue)
        focusMonitor.click()
        XCTAssertEqual(String(describing: focusMonitor.value), initialValue)
        XCTAssertTrue(app.windows["MacFlow"].exists)
    }

    private func navigate(to identifier: String) {
        let destination = element(identifier)
        XCTAssertTrue(destination.waitForExistence(timeout: 3), "Missing navigation item: \(identifier)")
        destination.click()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }
}
