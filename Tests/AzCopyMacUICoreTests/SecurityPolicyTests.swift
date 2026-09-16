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

    @Test("HTTP is rejected consistently across normalized remote endpoint types",
          arguments: ["blob", "file", "dfs"])
    func normalizedEndpoints(service: String) throws {
        for host in ["example.\(service).core.windows.net", "EXAMPLE.\(service.uppercased()).CORE.WINDOWS.NET"] {
            for prefix in ["", "--endpoint="] {
                let url = "HtTp://\(host)/container?sig=FAKE_SECRET"
                let invocation = AzCopyInvocation(
                    executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/azcopy"),
                    arguments: ["list", prefix + url]
                )
                #expect(throws: SecurityPolicy.Violation.insecureAzureURL(CredentialRedactor.redact(url))) {
                    try SecurityPolicy().validate(invocation: invocation)
                }
                var secureInvocation = invocation
                secureInvocation.arguments = ["list", prefix + "HtTpS://\(host)/container?sig=FAKE_SECRET"]
                try SecurityPolicy().validate(invocation: secureInvocation)
            }
        }
    }

    @Test("localhost HTTP requires the explicit emulator exception")
    func localhostException() throws {
        for host in ["localhost", "LOCALHOST", "localhost.", "127.0.0.1", "[::1]"] {
            let invocation = AzCopyInvocation(
                executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/azcopy"),
                arguments: ["list", "http://\(host):10000/account/container"]
            )
            #expect(throws: (any Error).self) { try SecurityPolicy().validate(invocation: invocation) }
            try SecurityPolicy(allowInsecureLocalhost: true).validate(invocation: invocation)
        }
        for host in ["localhost.example.com", ".localhost", "localhost..", "example.com", "storage.cloud.google.com", "s3.amazonaws.com"] {
            let url = "http://\(host)/container"
            let invocation = AzCopyInvocation(
                executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/azcopy"),
                arguments: ["list", url]
            )
            #expect(throws: SecurityPolicy.Violation.insecureAzureURL(url)) {
                try SecurityPolicy(allowInsecureLocalhost: true).validate(invocation: invocation)
            }
        }
    }

    @Test("HTTPS policy ignores local paths and non-URL flags")
    func localPaths() throws {
        let invocation = AzCopyInvocation(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/azcopy"),
            arguments: ["copy", "/path with spaces", "./relative", "--metadata=owner=team", "file:///local/path"]
        )
        try SecurityPolicy().validate(invocation: invocation)
    }

    @Test("policy error payload and descriptions never retain URL signatures")
    func redactedErrors() {
        let url = "HTTP://EXAMPLE.DFS.CORE.WINDOWS.NET/c?sv=1&sig=FAKE_SECRET"
        let invocation = AzCopyInvocation(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/azcopy"),
            arguments: ["--endpoint=" + url]
        )
        do {
            try SecurityPolicy().validate(invocation: invocation)
            Issue.record("Expected an HTTPS policy violation")
        } catch {
            #expect(!String(describing: error).contains("FAKE_SECRET"))
            #expect(!error.localizedDescription.contains("FAKE_SECRET"))
        }
        #expect(SecurityPolicy.Violation.insecureAzureURL(url).errorDescription?.contains("FAKE_SECRET") == false)
    }
}
