import Testing
@testable import AzCopyMacUICore

@Suite("CredentialRedactor")
struct CredentialRedactorTests {
    @Test("redacts SAS signatures in URLs")
    func redactsSAS() {
        let value = "https://example.blob.core.windows.net/c?sv=1&sig=supersecret&sp=rw"
        let redacted = CredentialRedactor.redact(value)

        #expect(redacted.contains("sig=%3Credacted%3E") || redacted.contains("sig=<redacted>"))
        #expect(!redacted.contains("supersecret"))
    }

    @Test("redacts sensitive environment assignments")
    func redactsEnvironmentAssignments() {
        let value = "AZCOPY_SPA_CLIENT_SECRET=secret azcopy copy"
        #expect(CredentialRedactor.redact(value) == "AZCOPY_SPA_CLIENT_SECRET=<redacted> azcopy copy")
    }

    @Test("redacts SAS flag assignments")
    func redactsSASFlagAssignments() {
        let value = "azcopy jobs resume job --source-sas=sv=1&sig=source --destination-sas=sv=1&sig=destination"
        let redacted = CredentialRedactor.redact(value)

        #expect(redacted.contains("--source-sas=<redacted>"))
        #expect(redacted.contains("--destination-sas=<redacted>"))
        #expect(!redacted.contains("sig=source"))
        #expect(!redacted.contains("sig=destination"))
    }

    @Test("preserves non-URL log text")
    func preservesNonURLLogText() {
        let value = "INFO: Name: AZCOPY_LOG_LOCATION\nCurrent Value: \nDescription: Overrides where log files are stored."
        #expect(CredentialRedactor.redact(value) == value)
    }

    @Test("redacts secret environment values in logs")
    func redactsForLog() {
        let log = CredentialRedactor.redactForLog(
            command: ["azcopy", "copy", "https://e.blob.core.windows.net/c?sig=secret"],
            environment: ["AZCOPY_SPA_CLIENT_SECRET": "secret", "AZCOPY_TENANT_ID": "tenant"]
        )

        #expect(log.contains("AZCOPY_SPA_CLIENT_SECRET=<redacted>"))
        #expect(log.contains("AZCOPY_TENANT_ID=tenant"))
        #expect(!log.contains("secret"))
    }

    @Test("redacts environment dictionary selectively")
    func redactsEnvironmentDictionary() {
        let redacted = CredentialRedactor.redact(environment: [
            "AZCOPY_SPA_CLIENT_SECRET": "secret",
            "AZCOPY_TENANT_ID": "tenant"
        ])

        #expect(redacted["AZCOPY_SPA_CLIENT_SECRET"] == "<redacted>")
        #expect(redacted["AZCOPY_TENANT_ID"] == "tenant")
    }
}
