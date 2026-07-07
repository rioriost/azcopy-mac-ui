import Foundation
import Testing
@testable import AzCopyMacUICore

@Suite("SecurityPolicy")
struct SecurityPolicyTests {
    @Test("rejects shell executable")
    func rejectsShellExecutable() {
        let invocation = AzCopyInvocation(
            executableURL: URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-lc", "azcopy --version"]
        )

        #expect(throws: SecurityPolicy.Violation.shellExecutableDisallowed) {
            try SecurityPolicy().validate(invocation: invocation)
        }
    }

    @Test("rejects insecure Azure storage URL")
    func rejectsInsecureAzureURL() {
        let invocation = AzCopyInvocation(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/azcopy"),
            arguments: ["list", "http://example.blob.core.windows.net/container"]
        )

        #expect(throws: SecurityPolicy.Violation.insecureAzureURL("http://example.blob.core.windows.net/container")) {
            try SecurityPolicy().validate(invocation: invocation)
        }
    }

    @Test("accepts HTTPS Azure storage URL")
    func acceptsHTTPSAzureURL() throws {
        let invocation = AzCopyInvocation(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/azcopy"),
            arguments: ["list", "https://example.blob.core.windows.net/container"]
        )

        try SecurityPolicy().validate(invocation: invocation)
    }

    @Test("rejects account key environment")
    func rejectsAccountKeyEnvironment() {
        let invocation = AzCopyInvocation(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/azcopy"),
            arguments: ["list", "https://example.blob.core.windows.net/container"],
            environment: ["AZCOPY_ACCOUNT_KEY": "key"]
        )

        #expect(throws: SecurityPolicy.Violation.accountKeyDirectAuthUnsupported) {
            try SecurityPolicy().validate(invocation: invocation)
        }
    }

    @Test("rejects relative executable")
    func rejectsRelativeExecutable() throws {
        let invocation = AzCopyInvocation(executableURL: try #require(URL(string: "azcopy")), arguments: [])
        #expect(throws: SecurityPolicy.Violation.executableIsNotAbsolute) {
            try SecurityPolicy().validate(invocation: invocation)
        }
    }

    @Test("violation descriptions are present")
    func violationDescriptions() {
        #expect(SecurityPolicy.Violation.missingExecutable.errorDescription?.isEmpty == false)
        #expect(SecurityPolicy.Violation.executableIsNotAbsolute.errorDescription?.isEmpty == false)
        #expect(SecurityPolicy.Violation.shellExecutableDisallowed.errorDescription?.isEmpty == false)
        #expect(SecurityPolicy.Violation.insecureAzureURL("http://example.blob.core.windows.net").errorDescription?.isEmpty == false)
        #expect(SecurityPolicy.Violation.accountKeyDirectAuthUnsupported.errorDescription?.isEmpty == false)
    }
}
