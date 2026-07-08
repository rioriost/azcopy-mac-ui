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
                extraFlags: ["--cap-mbps=10"]
            ),
            azCopyURL: executable
        )
        #expect(sync.arguments == ["sync", "/tmp/source", "https://example.blob.core.windows.net/container", "--delete-destination=true", "--cap-mbps=10"])

        let list = try builder.build(request: TransferRequest(action: .list, source: "https://example.blob.core.windows.net/container"), azCopyURL: executable)
        #expect(list.arguments == ["list", "https://example.blob.core.windows.net/container"])

        let remove = try builder.build(request: TransferRequest(action: .remove, source: "https://example.blob.core.windows.net/container/blob"), azCopyURL: executable)
        #expect(remove.arguments == ["remove", "https://example.blob.core.windows.net/container/blob"])

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
                extraFlags: ["--cap-mbps=500"],
                benchMode: "download",
                benchFileCount: "500",
                benchSizePerFile: "8M",
                benchNumberOfFolders: "4",
                benchDeleteTestData: false,
                benchPutMD5: true,
                benchCheckLength: false
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

        let environmentOnly = try builder.buildLogin(method: .azureCLI(tenantID: "tenant"), azCopyURL: executable)
        #expect(environmentOnly.arguments.isEmpty)
        #expect(environmentOnly.environment["AZCOPY_AUTO_LOGIN_TYPE"] == "AZCLI")
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
}
