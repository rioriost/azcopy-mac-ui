import Testing
@testable import AzCopyMacUICore

@Suite("CredentialRedactor")
struct CredentialRedactorTests {
    @Test("URL user credentials are hidden in argv and text output")
    func urlUserCredentials() {
        let url = "https://example-user:URL_PASSWORD@example.blob.core.windows.net/data?sig=URL_SIGNATURE"
        for value in [
            CredentialRedactor.redact(url),
            CredentialRedactor.redact(arguments: [url]).joined(),
            CredentialRedactor.redact(arguments: ["--source=\(url)"]).joined()
        ] {
            #expect(!value.contains("URL_PASSWORD"))
            #expect(!value.contains("example-user"))
            #expect(!value.contains("URL_SIGNATURE"))
            #expect(value.contains("example.blob.core.windows.net"))
        }
    }

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

    @Test("argv redaction pairs secret flags and values without changing boundaries")
    func redactsArguments() {
        let arguments = [
            "jobs", "resume", "job",
            "--source-sas", "sv=1&sig=FIRST_SECRET",
            "--destination-sas=SECOND_SECRET",
            "--source-sas", "SECRET WITH SPACES",
            "--DESTINATION-SAS=FOURTH_SECRET",
            "--log-level", "INFO",
            "AZCOPY_SPA_CLIENT_SECRET=SECRET WITH SPACES"
        ]
        let expected = [
            "jobs", "resume", "job",
            "--source-sas", "<redacted>",
            "--destination-sas=<redacted>",
            "--source-sas", "<redacted>",
            "--DESTINATION-SAS=<redacted>",
            "--log-level", "INFO",
            "AZCOPY_SPA_CLIENT_SECRET=<redacted>"
        ]
        #expect(CredentialRedactor.redact(arguments: arguments) == expected)
        #expect(CredentialRedactor.redact(arguments: ["--source-sas"]) == ["--source-sas"])
        #expect(CredentialRedactor.redact(arguments: ["--source-sas="]) == ["--source-sas=<redacted>"])
        let log = CredentialRedactor.redactForLog(command: arguments, environment: [:])
        for secret in ["FIRST_SECRET", "SECOND_SECRET", "SECRET WITH SPACES", "FOURTH_SECRET"] {
            #expect(!log.contains(secret))
        }
    }

    @Test("text redaction covers bare, mixed-case and escaped URL queries")
    func queryVariants() {
        let inputs = [
            "HTTPS://EXAMPLE.BLOB.CORE.WINDOWS.NET/c?SiG=FAKE_SECRET&sp=rw",
            "sv=1&sig=FAKE_SECRET&sp=rw",
            "?SIG=FAKE_SECRET",
            "sig=FAKE_SECRET",
            #"https:\/\/example.blob.core.windows.net\/c?sig=FAKE_SECRET\u0026sp=rw"#,
            #"https:\/\/example.blob.core.windows.net\/c?sv=1\u0026sig=FAKE_SECRET\u0026sp=rw"#,
            "https%3A%2F%2Fexample.blob.core.windows.net%2Fc%3Fsig%3DFAKE_SECRET%26sp%3Drw",
            "https://example.blob.core.windows.net/c?%73%69%67=FAKE_SECRET&sp=rw",
            "https://example.blob.core.windows.net/c?sig=prefix%26FAKE_SECRET&sp=rw",
            #"https:\/\/example.blob.core.windows.net\/c?\u0073\u0069\u0067\u003dFAKE_SECRET\u0026sp=rw"#,
            #"{"url":"HTTPS://example.dfs.core.windows.net/c?sv=1&sig=FAKE_SECRET"}"#,
            "signature=FAKE_SECRET&token=FAKE_SECRET&access_token=FAKE_SECRET&refresh_token=FAKE_SECRET",
            "--custom-url=HtTpS://example.file.core.windows.net/c?sig=FAKE_SECRET",
            "https://example.blob.core.windows.net/c?sv=1&sig=FAKE_SECRET&sig=FAKE_SECRET"
        ]
        for input in inputs {
            let redacted = CredentialRedactor.redact(input)
            #expect(!redacted.contains("FAKE_SECRET"))
            #expect(redacted.contains("<redacted>"))
        }
    }

    @Test("text redaction hides quoted assignments and separated SAS values")
    func assignmentVariants() {
        for input in [
            #"--source-sas "FAKE SECRET" --log-level INFO"#,
            #"--destination-sas='FAKE SECRET' --log-level INFO"#,
            "azcopy --SOURCE-SAS FAKE_SECRET --log-level INFO",
            #"AZCOPY_SPA_CLIENT_SECRET="FAKE SECRET" azcopy env"#,
            #"AZCOPY_SPA_CERT_PASSWORD='FAKE SECRET' azcopy env"#,
            "AZCOPY_ACCOUNT_KEY=FAKE_SECRET azcopy env"
        ] {
            let redacted = CredentialRedactor.redact(input)
            #expect(!redacted.contains("FAKE"))
            #expect(!redacted.contains("SECRET'"))
            #expect(redacted.contains("<redacted>"))
        }
    }

    @Test("display quoting round-trips every argument without shell expansion")
    func quotedArguments() throws {
        let arguments = ["azcopy", "folder with spaces", "", "single'quote", "\"double\"", "\\path", "日本語", "$HOME", "*.txt", "line\nbreak"]
        let displayed = arguments.map(CredentialRedactor.quoteArgument).joined(separator: " ")
        #expect(try ExtraFlagsParser.parse(displayed) == arguments)
    }

    @Test("URL argument signatures with literal whitespace and quotes are fully hidden")
    func urlArgumentBoundaries() {
        for prefix in ["", "--custom-url="] {
            let arguments = [prefix + #"HTTPS://example.blob.core.windows.net/c?sig=FAKE "SECRET" WITH SPACES&sp=r"#]
            let redacted = CredentialRedactor.redact(arguments: arguments)
            #expect(redacted.count == arguments.count)
            #expect(!redacted.joined().contains("FAKE"))
            #expect(!redacted.joined().contains("SECRET"))
            #expect(!redacted.joined().contains("SPACES"))
        }
    }

    @Test("unrelated environment values retain emptiness but embedded URLs are redacted")
    func environmentValues() {
        let redacted = CredentialRedactor.redact(environment: [
            "EMPTY": "",
            "ENDPOINT": "https://example.blob.core.windows.net/c?sig=FAKE_SECRET",
            "azcopy_spa_client_secret": "FAKE_SECRET"
        ])
        #expect(redacted["EMPTY"] == "")
        #expect(redacted["azcopy_spa_client_secret"] == "<redacted>")
        #expect(redacted["ENDPOINT"]?.contains("FAKE_SECRET") == false)
    }

    @Test("JSON credential values are redacted without losing surrounding fields")
    func jsonCredentials() {
        for key in ["access_token", "refresh_token", "sig", "AZCOPY_SPA_CLIENT_SECRET", "AZCOPY_SPA_CERT_PASSWORD", "client_secret", "password", "authorization"] {
            let input = "{\"ok\":true,\"\(key)\": \"FAKE \\\"SECRET\\\" WITH SPACES\", \"tenant\":\"public\"}"
            let redacted = CredentialRedactor.redact(input)
            #expect(!redacted.contains("FAKE"))
            #expect(!redacted.contains("WITH SPACES"))
            #expect(redacted.contains("\"\(key)\": \"<redacted>\""))
            #expect(redacted.contains("\"ok\":true"))
            #expect(redacted.contains("\"tenant\":\"public\""))
        }
        #expect(CredentialRedactor.redact(#"{'ACCESS_TOKEN': 'FAKE_SECRET'}"#) == #"{'ACCESS_TOKEN': "<redacted>"}"#)
    }

    @Test("Authorization header credentials are suppressed")
    func authorizationHeaders() {
        for input in [
            "Authorization: Bearer FAKE_SECRET",
            "authorization=Bearer FAKE_SECRET",
            "AUTHORIZATION: Basic FAKE_SECRET",
            #"{"Authorization":"Bearer FAKE_SECRET"}"#
        ] {
            let redacted = CredentialRedactor.redact(input)
            #expect(!redacted.contains("FAKE_SECRET"))
            #expect(redacted.contains("<redacted>"))
        }
        #expect(CredentialRedactor.redact("Basic instructions are public") == "Basic instructions are public")
    }
}
