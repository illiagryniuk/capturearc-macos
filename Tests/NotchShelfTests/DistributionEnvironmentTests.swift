import XCTest
@testable import NotchShelf

final class DistributionEnvironmentTests: XCTestCase {
    func testExplicitAppStoreBuildRequiresFolderAuthorization() {
        XCTAssertEqual(
            DistributionChannel.resolve(
                distributionValue: "app-store",
                sandboxContainerID: nil
            ),
            .appStore
        )
        XCTAssertTrue(
            DistributionChannel.appStore.requiresExplicitCaptureFolderAuthorization
        )
    }

    func testSandboxEnvironmentUsesAppStoreSafetyPath() {
        XCTAssertEqual(
            DistributionChannel.resolve(
                distributionValue: nil,
                sandboxContainerID: "com.illiagryniuk.capturearc"
            ),
            .appStore
        )
    }

    func testLocalBuildKeepsAutomaticScreenshotDiscovery() {
        XCTAssertEqual(
            DistributionChannel.resolve(
                distributionValue: "local",
                sandboxContainerID: nil
            ),
            .local
        )
        XCTAssertFalse(
            DistributionChannel.local.requiresExplicitCaptureFolderAuthorization
        )
    }
}
