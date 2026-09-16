import Foundation
import Testing
@testable import AzCopyMacUICore

@Suite("AzCopyCommandBuilder")
struct AzCopyCommandBuilderTests {
    private let builder = AzCopyCommandBuilder()
    private let executable = URL(fileURLWithPath: "/opt/homebrew/bin/azcopy")

    @Test("builds copy command with safe arguments")
    func buildsCopyCommand() throws {
        let request = TransferRequest(
            action: .copy,
            source: "/tmp/source",
            destination: "https://example.blob.core.windows.net/container",
            recursive: true,
            dryRun: true,
            overwrite: false,
            authentication: .azureCLI(tenantID: "tenant")
        )

        let invocation = try builder.build(request: request, azCopyURL: executable)

        #expect(invocation.executableURL == executable)
        #expect(invocation.arguments == [
            "copy",
            "/tmp/source",
            "https://example.blob.core.windows.net/container",
            "--recursive=true",
            "--dry-run",
            "--overwrite=false"
        ])
        #expect(invocation.environment["AZCOPY_AUTO_LOGIN_TYPE"] == "AZCLI")
        #expect(invocation.environment["AZCOPY_TENANT_ID"] == "tenant")
    }

    @Test("requires destination for copy")
    func requiresDestination() {
        let request = TransferRequest(action: .copy, source: "/tmp/source")
        #expect(throws: AzCopyCommandBuilder.BuilderError.missingDestination) {
            _ = try builder.build(request: request, azCopyURL: executable)
        }
    }

    @Test("rejects direct account key auth")
    func rejectsAccountKeyAuth() {
        let request = TransferRequest(
            action: .list,
            source: "https://example.blob.core.windows.net/container",
            authentication: .accountKeyDerivedSAS
        )
        #expect(throws: AzCopyCommandBuilder.BuilderError.unsupportedAccountKeyDirectAuth) {
            _ = try builder.build(request: request, azCopyURL: executable)
        }
    }

    @Test("builds command variants")
    func buildsCommandVariants() throws {
        let sync = try builder.build(
            request: TransferRequest(
                action: .sync,
                source: "/tmp/source",
                destination: "https://example.blob.core.windows.net/container",
                deleteDestination: true,
                capMbps: "10"
            ),
            azCopyURL: executable
        )
        #expect(sync.arguments == ["sync", "/tmp/source", "https://example.blob.core.windows.net/container", "--recursive=false", "--delete-destination=true", "--cap-mbps=10"])

        let list = try builder.build(request: TransferRequest(action: .list, source: "https://example.blob.core.windows.net/container"), azCopyURL: executable)
        #expect(list.arguments == ["list", "https://example.blob.core.windows.net/container"])

        let remove = try builder.build(request: TransferRequest(action: .remove, source: "https://example.blob.core.windows.net/container/blob"), azCopyURL: executable)
        #expect(remove.arguments == ["remove", "https://example.blob.core.windows.net/container/blob", "--recursive=false"])

        let jobs = try builder.build(request: TransferRequest(action: .jobsList), azCopyURL: executable)
        #expect(jobs.arguments == ["jobs", "list"])

        let status = try builder.build(request: TransferRequest(action: .loginStatus), azCopyURL: executable)
        #expect(status.arguments == ["login", "status"])

        let logout = try builder.build(request: TransferRequest(action: .logout), azCopyURL: executable)
        #expect(logout.arguments == ["logout"])
    }

    @Test("builds extended command variants")
    func buildsExtendedCommandVariants() throws {
        let bench = try builder.build(
            request: TransferRequest(
                action: .bench,
                source: "https://example.blob.core.windows.net/container",
                benchMode: "download",
                benchFileCount: "500",
                benchSizePerFile: "8M",
                benchNumberOfFolders: "4",
                benchDeleteTestData: false,
                benchPutMD5: true,
                benchCheckLength: false,
                capMbps: "500"
            ),
            azCopyURL: executable
        )
        #expect(bench.arguments == [
            "bench",
            "https://example.blob.core.windows.net/container",
            "--mode=download",
            "--file-count=500",
            "--size-per-file=8M",
            "--number-of-folders=4",
            "--delete-test-data=false",
            "--put-md5",
            "--check-length=false",
            "--cap-mbps=500"
        ])

        let make = try builder.build(
            request: TransferRequest(
                action: .make,
                source: "https://example.blob.core.windows.net/container",
                makeQuotaGB: "100"
            ),
            azCopyURL: executable
        )
        #expect(make.arguments == ["make", "https://example.blob.core.windows.net/container", "--quota-gb=100"])

        let setProperties = try builder.build(
            request: TransferRequest(
                action: .setProperties,
                source: "https://example.blob.core.windows.net/container/path",
                recursive: true,
                dryRun: true,
                blockBlobTier: "Archive",
                rehydratePriority: "High",
                metadata: "owner=team",
                blobTags: "project=demo",
                includePath: "a/b",
                excludePath: "tmp",
                listOfFiles: "/tmp/files.txt"
            ),
            azCopyURL: executable
        )
        #expect(setProperties.arguments == [
            "set-properties",
            "https://example.blob.core.windows.net/container/path",
            "--block-blob-tier=Archive",
            "--rehydrate-priority=High",
            "--metadata=owner=team",
            "--blob-tags=project=demo",
            "--include-path=a/b",
            "--exclude-path=tmp",
            "--list-of-files=/tmp/files.txt",
            "--recursive=true",
            "--dry-run"
        ])

        let env = try builder.build(
            request: TransferRequest(action: .env, showSensitiveEnvironment: true),
            azCopyURL: executable
        )
        #expect(env.arguments == ["env", "--show-sensitive"])
    }

    @Test("builds job subcommands")
    func buildsJobSubcommands() throws {
        let show = try builder.build(
            request: TransferRequest(action: .jobsShow, jobID: "job-1", jobTransferStatus: "Failed"),
            azCopyURL: executable
        )
        #expect(show.arguments == ["jobs", "show", "job-1", "--with-status=Failed"])

        let resume = try builder.build(
            request: TransferRequest(
                action: .jobsResume,
                jobID: "job-1",
                sourceSAS: "sv=1&sig=source",
                destinationSAS: "sv=1&sig=destination",
                includePath: "failed-a",
                excludePath: "failed-b"
            ),
            azCopyURL: executable
        )
        #expect(resume.arguments == [
            "jobs",
            "resume",
            "job-1",
            "--source-sas=sv=1&sig=source",
            "--destination-sas=sv=1&sig=destination",
            "--include=failed-a",
            "--exclude=failed-b"
        ])
        #expect(!resume.redactedPreview.contains("sig=source"))
        #expect(!resume.redactedPreview.contains("sig=destination"))

        let remove = try builder.build(
            request: TransferRequest(action: .jobsRemove, jobID: "job-1"),
            azCopyURL: executable
        )
        #expect(remove.arguments == ["jobs", "remove", "job-1"])

        let clean = try builder.build(request: TransferRequest(action: .jobsClean), azCopyURL: executable)
        #expect(clean.arguments == ["jobs", "clean"])
    }

    @Test("builds login invocation")
    func buildsLoginInvocation() throws {
        let login = try builder.buildLogin(method: .userIdentity(tenantID: "tenant"), azCopyURL: executable)
        #expect(login.arguments == ["login", "--tenant-id=tenant"])

        let deviceCode = try builder.buildLogin(method: .deviceCodeEnvironment, azCopyURL: executable)
        #expect(deviceCode.arguments == ["login"])

        let tenantDeviceCode = try builder.buildLogin(method: .deviceCode(tenantID: " tenant "), azCopyURL: executable)
        #expect(tenantDeviceCode.arguments == ["login", "--tenant-id=tenant"])
        #expect(tenantDeviceCode.environment == ["AZCOPY_AUTO_LOGIN_TYPE": "DEVICE", "AZCOPY_TENANT_ID": "tenant"])
    }

    @Test("redacted preview hides SAS signature")
    func redactedPreview() {
        let invocation = AzCopyInvocation(
            executableURL: executable,
            arguments: ["copy", "https://example.blob.core.windows.net/c?sig=secret", "/tmp/out"]
        )

        #expect(!invocation.redactedPreview.contains("secret"))
    }

    @Test("builder errors have descriptions")
    func builderErrorDescriptions() {
        #expect(AzCopyCommandBuilder.BuilderError.missingSource.errorDescription?.isEmpty == false)
        #expect(AzCopyCommandBuilder.BuilderError.missingDestination.errorDescription?.isEmpty == false)
        #expect(AzCopyCommandBuilder.BuilderError.unsupportedAccountKeyDirectAuth.errorDescription?.isEmpty == false)
    }

    @Test("recursive is explicit for both settings on every supported action",
          arguments: [TransferAction.copy, .sync, .remove, .setProperties], [false, true])
    func recursiveIsExplicit(action: TransferAction, recursive: Bool) throws {
        let invocation = try builder.build(
            request: TransferRequest(
                action: action,
                source: "/test-data/source",
                destination: "https://example.blob.core.windows.net/container",
                recursive: recursive,
                deleteDestination: action == .sync ? true : nil
            ),
            azCopyURL: executable
        )
        #expect(invocation.arguments.filter { $0.hasPrefix("--recursive") } == ["--recursive=\(recursive)"])
        if action == .sync {
            #expect(invocation.arguments.contains("--delete-destination=true"))
        }
    }

    @Test("UI safety flag overrides are rejected in equals and separate forms",
          arguments: [TransferAction.copy, .sync, .remove, .setProperties])
    func rejectsSafetyOverrides(action: TransferAction) {
        for flag in ["--dry-run", "--recursive", "--overwrite", "--delete-destination"] {
            for flags in [[flag + "=false"], [flag, "false"], [flag], [flag.uppercased() + "=true"]] {
                let request = TransferRequest(
                    action: action,
                    source: "/test-data/source",
                    destination: "https://example.blob.core.windows.net/container",
                    recursive: false,
                    dryRun: true,
                    extraFlags: flags
                )
                #expect(throws: AzCopyCommandBuilder.BuilderError.reservedExtraFlag(flag)) {
                    _ = try builder.build(request: request, azCopyURL: executable)
                }
            }
        }
    }

    @Test("operation-specific form options cannot be overridden through extra flags")
    func rejectsFormOptionOverrides() {
        let cases: [(TransferAction, String)] = [
            (.bench, "--delete-test-data"), (.make, "--quota-gb"),
            (.setProperties, "--metadata"), (.env, "--show-sensitive"),
            (.jobsShow, "--with-status"), (.jobsResume, "--source-sas"),
            (.copy, "--cap-mbps"), (.sync, "--cap-mbps"), (.bench, "--cap-mbps"),
            (.copy, "--include-pattern"), (.copy, "--exclude-pattern"),
            (.setProperties, "--include-pattern"), (.remove, "--exclude-pattern")
        ]
        for (action, flag) in cases {
            for flags in [[flag + "=value"], [flag, "value"]] {
                #expect(throws: AzCopyCommandBuilder.BuilderError.reservedExtraFlag(flag)) {
                    _ = try builder.build(
                        request: TransferRequest(action: action, source: "/test-data/source", extraFlags: flags, jobID: "job-1"),
                        azCopyURL: executable
                    )
                }
            }
        }
    }

    @Test("additional flags cannot terminate parsing of generated protections")
    func rejectsArgumentTerminator() {
        for flags in [["--"], ["--", "--recursive=true"], ["--include-path", "--", "--dry-run=false"]] {
            #expect(throws: AzCopyCommandBuilder.BuilderError.argumentTerminatorDisallowed) {
                _ = try builder.build(
                    request: TransferRequest(action: .remove, source: "/test-data/source", dryRun: true, extraFlags: flags),
                    azCopyURL: executable
                )
            }
        }
        for source in ["--", "--dry-run=false", "-relative-path"] {
            #expect(throws: AzCopyCommandBuilder.BuilderError.invalidArgument) {
                _ = try builder.build(
                    request: TransferRequest(action: .remove, source: source, dryRun: true),
                    azCopyURL: executable
                )
            }
        }
    }

    @Test("valid additional arguments retain their exact boundaries")
    func preservesAdditionalFlags() throws {
        let extra = try ExtraFlagsParser.parse(#"--include-path="folder with spaces" --log-level INFO --metadata 'owner=チーム A' --source-sas 'sv=1&sig=FAKE_SECRET' --custom="literal --recursive=false""#)
        let invocation = try builder.build(
            request: TransferRequest(
                action: .copy,
                source: "/test-data/source",
                destination: "/test-data/destination",
                extraFlags: extra
            ),
            azCopyURL: executable
        )
        #expect(Array(invocation.arguments.suffix(extra.count)) == extra)
        #expect(try ExtraFlagsParser.parse(invocation.redactedPreview) == CredentialRedactor.redact(arguments: [executable.path] + invocation.arguments))
        #expect(!invocation.redactedPreview.contains("FAKE_SECRET"))
    }

    @Test("unused authentication does not block local administration",
          arguments: [TransferAction.env, .jobsList, .jobsShow, .jobsRemove, .jobsClean, .loginStatus, .logout])
    func unusedAuthentication(action: TransferAction) throws {
        for method in [
            AuthenticationMethod.servicePrincipalSecret(applicationID: "", tenantID: "", clientSecret: ""),
            .managedIdentityObjectID("legacy"),
            .accountKeyDerivedSAS
        ] {
            let invocation = try builder.build(
                request: TransferRequest(action: action, authentication: method, jobID: "job-1"),
                azCopyURL: executable
            )
            #expect(invocation.environment.isEmpty)
        }
    }

    @Test("transfer and sign-in validate credentials before invocation")
    func validatesRequiredAuthentication() {
        let method = AuthenticationMethod.servicePrincipalSecret(applicationID: "app", tenantID: "tenant", clientSecret: "")
        #expect(throws: AuthenticationMethod.ValidationError.missingRequiredField("Client secret")) {
            _ = try builder.build(
                request: TransferRequest(action: .list, source: "https://example.blob.core.windows.net/c", authentication: method),
                azCopyURL: executable
            )
        }
        #expect(throws: AuthenticationMethod.ValidationError.missingRequiredField("Client secret")) {
            _ = try builder.buildLogin(method: method, azCopyURL: executable)
        }
        #expect(throws: AuthenticationMethod.ValidationError.managedIdentityObjectIDUnsupported) {
            _ = try builder.buildLogin(method: .managedIdentityObjectID("old-object-id"), azCopyURL: executable)
        }
        #expect(throws: AuthenticationMethod.ValidationError.managedIdentityObjectIDUnsupported) {
            _ = try builder.build(
                request: TransferRequest(action: .jobsResume, authentication: .managedIdentityObjectID("legacy"), jobID: "job-1"),
                azCopyURL: executable
            )
        }
    }

    @Test("unsupported sign-in produces guidance instead of an empty command")
    func unsupportedLogin() {
        for method in [AuthenticationMethod.azureCLI(tenantID: nil), .azurePowerShell(tenantID: nil), .sas] {
            #expect(throws: AzCopyCommandBuilder.BuilderError.unsupportedLoginMethod(method.signInGuidance)) {
                _ = try builder.buildLogin(method: method, azCopyURL: executable)
            }
            #expect(!method.signInGuidance.isEmpty)
        }
    }

    @Test("shared capabilities match the supported operation controls")
    func sharedCapabilities() {
        for action in TransferAction.allCases {
            let recursive = [TransferAction.copy, .sync, .remove, .setProperties].contains(action)
            #expect(action.supportsRecursive == recursive)
            #expect(action.supportsDryRun == recursive)
            #expect(action.supportsPatternFlags == recursive)
            #expect(action.supportsCapMbps == [TransferAction.copy, .sync, .bench].contains(action))
        }
    }

    @Test("typed rate and pattern controls follow the shared capabilities",
          arguments: TransferAction.allCases)
    func typedFormFlags(action: TransferAction) throws {
        let invocation = try builder.build(
            request: TransferRequest(
                action: action,
                source: "/test-data/source",
                destination: "/test-data/destination",
                jobID: "job-1",
                capMbps: " 100 ",
                includePattern: " *.txt;report with spaces ",
                excludePattern: " *.bak "
            ),
            azCopyURL: executable
        )
        #expect(invocation.arguments.contains("--cap-mbps=100") == action.supportsCapMbps)
        #expect(invocation.arguments.contains("--include-pattern=*.txt;report with spaces") == action.supportsPatternFlags)
        #expect(invocation.arguments.contains("--exclude-pattern=*.bak") == action.supportsPatternFlags)
    }

    @Test("blank typed controls are omitted without permitting extra-flag overrides")
    func blankTypedFormFlags() throws {
        let invocation = try builder.build(
            request: TransferRequest(
                action: .copy, source: "/test-data/source", destination: "/test-data/destination",
                capMbps: " ", includePattern: "\t", excludePattern: "\n"
            ),
            azCopyURL: executable
        )
        #expect(invocation.arguments == ["copy", "/test-data/source", "/test-data/destination", "--recursive=false"])
    }

    @Test("unsupported action options are not emitted")
    func unsupportedOptions() throws {
        let invocation = try builder.build(
            request: TransferRequest(action: .list, source: "/test-data/source", recursive: true, dryRun: true, overwrite: true, deleteDestination: true),
            azCopyURL: executable
        )
        #expect(invocation.arguments == ["list", "/test-data/source"])
    }

    @Test("null characters are rejected instead of being truncated by process launch")
    func rejectsNullArgument() {
        for flags in [["--log-level=\0INFO"], ["\0--dry-run=false"]] {
            #expect(throws: AzCopyCommandBuilder.BuilderError.invalidArgument) {
                _ = try builder.build(request: TransferRequest(action: .env, extraFlags: flags), azCopyURL: executable)
            }
        }
    }
}

@Suite("ExtraFlagsParser")
struct ExtraFlagsParserTests {
    @Test("documented quoting and escaping preserve argv")
    func tokenization() throws {
        let cases: [(String, [String])] = [
            (" \n\t ", []),
            (#"--include-path="folder with spaces""#, ["--include-path=folder with spaces"]),
            (#"--name='日本語 フォルダー' --name=plain"#, ["--name=日本語 フォルダー", "--name=plain"]),
            (#"'single "quote"' "double 'quote'""#, [#"single "quote""#, "double 'quote'"]),
            (#"'' "" --empty="" a""b"#, ["", "", "--empty=", "ab"]),
            (#"escaped\ space \"quote\" "\\" '\literal\text'"#, ["escaped space", "\"quote\"", "\\", "\\literal\\text"]),
            (#"one" two"' three'"#, ["one two three"]),
            (#"$HOME $(whoami) `id` *.txt ~ > ; |"#, ["$HOME", "$(whoami)", "`id`", "*.txt", "~", ">", ";", "|"]),
            ("a\nb\tc\r\nd", ["a", "b", "c", "d"])
        ]
        for (text, expected) in cases {
            #expect(try ExtraFlagsParser.parse(text) == expected)
        }
    }

    @Test("malformed quoting fails without including sensitive input in errors")
    func malformedInput() {
        for text in [#""FAKE_SECRET"#, #"'FAKE_SECRET"#] {
            #expect(throws: ExtraFlagsParser.ParseError.unterminatedQuote) {
                try ExtraFlagsParser.parse(text)
            }
        }
        #expect(throws: ExtraFlagsParser.ParseError.trailingEscape) {
            try ExtraFlagsParser.parse("FAKE_SECRET\\")
        }
        #expect(throws: ExtraFlagsParser.ParseError.nullCharacter) {
            try ExtraFlagsParser.parse("--flag=\0")
        }
    }
}
