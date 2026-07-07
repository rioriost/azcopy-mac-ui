import Foundation
import Testing
@testable import AzCopyMacUICore

private struct FakeFileChecker: FileChecking {
    var executablePaths: Set<String>

    func isExecutableFile(atPath path: String) -> Bool {
        executablePaths.contains(path)
    }
}

@Suite("AzCopyLocator")
struct AzCopyLocatorTests {
    @Test("prefers Apple Silicon Homebrew path")
    func prefersHomebrewPath() throws {
        let locator = AzCopyLocator(
            fileChecker: FakeFileChecker(executablePaths: [
                AzCopyLocator.homebrewAppleSiliconPath,
                "/tmp/bin/azcopy"
            ]),
            environmentPath: "/tmp/bin"
        )

        #expect(try locator.locate().path == AzCopyLocator.homebrewAppleSiliconPath)
    }

    @Test("falls back to PATH")
    func fallsBackToPath() throws {
        let locator = AzCopyLocator(
            fileChecker: FakeFileChecker(executablePaths: ["/tmp/bin/azcopy"]),
            environmentPath: "/tmp/bin"
        )

        #expect(try locator.locate().path == "/tmp/bin/azcopy")
    }

    @Test("throws when missing")
    func throwsWhenMissing() {
        let locator = AzCopyLocator(
            fileChecker: FakeFileChecker(executablePaths: []),
            environmentPath: "/tmp/bin"
        )

        #expect(throws: AzCopyLocator.LocatorError.notFound) {
            _ = try locator.locate()
        }
    }

    @Test("checks preferred Homebrew path")
    func checksPreferredPath() {
        let locator = AzCopyLocator(fileChecker: FakeFileChecker(executablePaths: []), environmentPath: "")
        #expect(locator.isPreferredHomebrewPath(URL(fileURLWithPath: AzCopyLocator.homebrewAppleSiliconPath)))
        #expect(!locator.isPreferredHomebrewPath(URL(fileURLWithPath: "/tmp/bin/azcopy")))
        #expect(AzCopyLocator.LocatorError.notFound.errorDescription?.isEmpty == false)
    }
}
