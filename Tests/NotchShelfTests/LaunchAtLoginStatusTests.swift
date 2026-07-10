import ServiceManagement
import XCTest
@testable import NotchShelf

final class LaunchAtLoginStatusTests: XCTestCase {
    func testMapsServiceManagementStatuses() {
        XCTAssertEqual(
            LaunchAtLoginStatus(serviceStatus: .notRegistered),
            .notRegistered
        )
        XCTAssertEqual(
            LaunchAtLoginStatus(serviceStatus: .enabled),
            .enabled
        )
        XCTAssertEqual(
            LaunchAtLoginStatus(serviceStatus: .requiresApproval),
            .requiresApproval
        )
        XCTAssertEqual(
            LaunchAtLoginStatus(serviceStatus: .notFound),
            .notRegistered
        )
    }

    func testRegisteredStatusesKeepPreferenceEnabled() {
        XCTAssertFalse(LaunchAtLoginStatus.notRegistered.isEnabled)
        XCTAssertTrue(LaunchAtLoginStatus.enabled.isEnabled)
        XCTAssertTrue(LaunchAtLoginStatus.requiresApproval.isEnabled)
        XCTAssertFalse(LaunchAtLoginStatus.unavailable.isEnabled)
    }

    func testUnavailableStatusExplainsSignedBundleRequirement() {
        let helper = LaunchAtLoginStatus.unavailable.helper

        XCTAssertTrue(helper.contains("properly signed"))
        XCTAssertTrue(helper.contains("Applications"))
    }
}
