import Foundation
import Testing
@testable import AzCopyMacUICore

@Suite("AzCopyProcessRunner")
struct AzCopyProcessRunnerTests {
    @Test("runs absolute executable without shell")
    func runsExecutable() async throws {
        let runner = AzCopyProcessRunner()
        let invocation = AzCopyInvocation(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello"]
        )

        let result = try await runner.run(invocation)

        #expect(result.exitCode == 0)
        #expect(result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
    }

    @Test("surfaces validation errors")
    func surfacesValidationErrors() async {
        let runner = AzCopyProcessRunner()
        let invocation = AzCopyInvocation(
            executableURL: URL(fileURLWithPath: "/bin/bash"),
            arguments: []
        )

        await #expect(throws: AzCopyProcessRunner.RunnerError.validationFailed(SecurityPolicy.Violation.shellExecutableDisallowed.localizedDescription)) {
            _ = try await runner.run(invocation)
        }
    }

    @Test("runner error descriptions are present")
    func runnerErrorDescriptions() {
        #expect(AzCopyProcessRunner.RunnerError.validationFailed("bad").errorDescription?.isEmpty == false)
        #expect(AzCopyProcessRunner.RunnerError.launchFailed("bad").errorDescription?.isEmpty == false)
    }
}
