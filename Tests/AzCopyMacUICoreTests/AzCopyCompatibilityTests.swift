import Foundation
import Testing
@testable import AzCopyMacUICore

/// Opt-in integration coverage: no credentials or network are needed for CLI checks.
/// Blob checks accept only the disposable loopback Azurite instance started by the script.
@Suite("Installed AzCopy compatibility", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["AZCOPY_TEST_EXECUTABLE"] != nil),
       .timeLimit(.minutes(2)))
struct AzCopyCompatibilityTests {
    @Test("all GUI commands and managed flags are accepted by the real CLI")
    func commandSurface() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let version = try await fixture.run(arguments: ["--version"])
        #expect(version.output.contains("azcopy version"))
        print(version.output.trimmingCharacters(in: .whitespacesAndNewlines))

        for action in TransferAction.allCases {
            let request = TransferRequest(
                action: action, source: "https://example.blob.core.windows.net/compat",
                destination: "https://example.blob.core.windows.net/destination",
                recursive: true, dryRun: true, overwrite: false, deleteDestination: false,
                extraFlags: ["--help"], authentication: .sas,
                jobID: "00000000-0000-0000-0000-000000000000", jobTransferStatus: "Failed",
                sourceSAS: "sig=fixture", destinationSAS: "sig=fixture",
                benchFileCount: "1", benchSizePerFile: "1K", benchNumberOfFolders: "1",
                benchDeleteTestData: false, benchPutMD5: true, benchCheckLength: false,
                makeQuotaGB: "1", blockBlobTier: "Cool", pageBlobTier: "P10",
                rehydratePriority: "High", metadata: "owner=test", blobTags: "owner=test",
                includePath: "one", excludePath: "two", listOfFiles: "/tmp/fixture-files",
                showSensitiveEnvironment: true, capMbps: "10",
                includePattern: "*.txt", excludePattern: "*.tmp"
            )
            let result = try await fixture.run(request)
            #expect(result.output.contains("Usage:"), "Missing help for \(action)")
        }
        // Ensure this CLI actually rejects unknown options even with --help.
        let invalid = try await fixture.run(arguments: ["copy", "--not-an-azcopy-option", "--help"], expectSuccess: false)
        #expect(invalid.exitCode != 0)
        #expect((invalid.output + invalid.errorOutput).contains("unknown flag"))

        let methods: [AuthenticationMethod] = [
            .userIdentity(tenantID: "fixture"), .deviceCode(tenantID: "fixture"), .deviceCodeEnvironment,
            .servicePrincipalSecret(applicationID: "fixture", tenantID: "fixture", clientSecret: "fixture-secret"),
            .servicePrincipalCertificate(applicationID: "fixture", tenantID: "fixture", certificatePath: "/tmp/fixture.pem", certificatePassword: nil),
            .managedIdentitySystem, .managedIdentityClientID("fixture"), .managedIdentityResourceID("fixture")
        ]
        for method in methods {
            var invocation = try AzCopyCommandBuilder().buildLogin(method: method, azCopyURL: fixture.executable)
            invocation.arguments.append("--help") // Parses options; never signs in or accesses Keychain.
            let result = try await fixture.execute(invocation)
            #expect(result.output.contains("Usage:"))
        }
    }

    @Test("environment and empty job history execute in isolated directories")
    func localCommands() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let environment = try await fixture.run(TransferRequest(action: .env))
        #expect(environment.output.contains("AZCOPY_LOG_LOCATION"))
        _ = try await fixture.run(TransferRequest(action: .jobsList))
        _ = try await fixture.run(TransferRequest(action: .jobsClean))
    }

    @Test("SAS Blob round trip, filtering, sync, properties, dry runs and removal",
          .enabled(if: ProcessInfo.processInfo.environment["AZCOPY_TEST_BLOB_URL"] != nil))
    func blobRoundTrip() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let rawURL = try #require(ProcessInfo.processInfo.environment["AZCOPY_TEST_BLOB_URL"])
        let endpoint = try #require(URLComponents(string: rawURL))
        try #require(endpoint.scheme == "http" && endpoint.host == "127.0.0.1"
                     && endpoint.path == "/azcopytest/compat" && endpoint.port != nil,
                     "Only the local disposable Azurite fixture is permitted")
        let source = fixture.directory.appendingPathComponent("source files")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("nested"), withIntermediateDirectories: true)
        let original = Data("AzCopy compatibility 日本語\n".utf8)
        try original.write(to: source.appendingPathComponent("hello world.txt"))
        try Data("nested payload".utf8).write(to: source.appendingPathComponent("nested/child.txt"))
        try Data("excluded".utf8).write(to: source.appendingPathComponent("skip.tmp"))

        func remote(_ path: String) -> String {
            var result = endpoint
            result.path += path
            return result.string!
        }
        func listing() async throws -> String {
            try await fixture.run(TransferRequest(action: .list, source: rawURL, authentication: .sas)).output
        }
        var upload = TransferRequest(action: .copy, source: source.path + "/*", destination: rawURL,
                                     recursive: true, dryRun: true, overwrite: true, extraFlags: ["--put-md5"], authentication: .sas,
                                     includePattern: "*.txt", excludePattern: "*.tmp")
        let dryUpload = try await fixture.run(upload)
        #expect(dryUpload.output.contains("DRYRUN"))
        #expect(!(try await listing()).contains("hello world.txt"))
        upload.dryRun = false
        let uploaded = try await fixture.run(upload)
        #expect(uploaded.output.contains("Completed"))
        let uploadedList = try await listing()
        #expect(uploadedList.contains("hello world.txt"))
        #expect(uploadedList.contains("nested/child.txt"))
        #expect(!uploadedList.contains("skip.tmp"))

        let downloaded = fixture.directory.appendingPathComponent("downloaded.txt")
        _ = try await fixture.run(TransferRequest(action: .copy, source: remote("/hello world.txt"),
                                                 destination: downloaded.path, overwrite: true, authentication: .sas))
        #expect(try Data(contentsOf: downloaded) == original)

        _ = try await fixture.run(TransferRequest(action: .setProperties, source: remote("/hello world.txt"),
                                                 authentication: .sas, metadata: "owner=compatibility"))
        let (_, propertyResponse) = try await URLSession.shared.data(from: URL(string: remote("/hello world.txt"))!)
        #expect((propertyResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "x-ms-meta-owner") == "compatibility")

        var sync = TransferRequest(action: .sync, source: source.path, destination: rawURL,
                                   recursive: true, dryRun: true, deleteDestination: false, authentication: .sas,
                                   includePattern: "*.txt")
        let updated = Data("Changed content for sync verification\n".utf8)
        try updated.write(to: source.appendingPathComponent("hello world.txt"))
        // MD5 comparison avoids relying on filesystem/emulator timestamp resolution.
        sync.extraFlags = ["--compare-hash=MD5"]
        let drySync = try await fixture.run(sync)
        #expect(drySync.output.contains("DRYRUN"))
        _ = try await fixture.run(TransferRequest(action: .copy, source: remote("/hello world.txt"),
                                                 destination: downloaded.path, overwrite: true, authentication: .sas))
        #expect(try Data(contentsOf: downloaded) == original)
        sync.dryRun = false
        _ = try await fixture.run(sync)
        _ = try await fixture.run(TransferRequest(action: .copy, source: remote("/hello world.txt"),
                                                 destination: downloaded.path, overwrite: true, authentication: .sas))
        #expect(try Data(contentsOf: downloaded) == updated)

        let jobs = try await fixture.run(TransferRequest(action: .jobsList))
        let jobID = try #require(jobs.output.firstMatch(of: /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/)).output
        _ = try await fixture.run(TransferRequest(action: .jobsShow, jobID: String(jobID)))
        _ = try await fixture.run(TransferRequest(action: .jobsRemove, jobID: String(jobID)))

        var remove = TransferRequest(action: .remove, source: remote("/hello world.txt"), dryRun: true, authentication: .sas)
        let dryRemove = try await fixture.run(remove)
        #expect(dryRemove.output.contains("DRYRUN"))
        #expect((try await listing()).contains("hello world.txt"))
        remove.dryRun = false
        _ = try await fixture.run(remove)
        let finalList = try await listing()
        #expect(!finalList.contains("hello world.txt"))
        #expect(finalList.contains("nested/child.txt"))
    }

    private struct Fixture {
        let executable: URL
        let directory: URL
        let runner = AzCopyProcessRunner(securityPolicy: SecurityPolicy(allowInsecureLocalhost: true))

        init() throws {
            executable = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["AZCOPY_TEST_EXECUTABLE"]))
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("azcopy-compat-\(UUID())")
            for path in ["home", "logs", "plans"] {
                try FileManager.default.createDirectory(at: directory.appendingPathComponent(path), withIntermediateDirectories: true)
            }
        }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }

        func run(_ request: TransferRequest) async throws -> AzCopyRunResult {
            var request = request
            // Loopback URLs cannot infer a storage service from an Azure hostname.
            // These are supported Additional flags; production HTTPS behavior is unchanged.
            if request.source.hasPrefix("http://127.0.0.1:") || (request.destination?.hasPrefix("http://127.0.0.1:") == true) {
                switch request.action {
                case .copy, .sync:
                    request.extraFlags.append(request.source.hasPrefix("http://") ? "--from-to=BlobLocal" : "--from-to=LocalBlob")
                case .list: request.extraFlags.append("--location=Blob")
                case .remove: request.extraFlags.append("--from-to=BlobTrash")
                case .setProperties: request.extraFlags.append("--from-to=BlobNone")
                default: break
                }
            }
            return try await execute(AzCopyCommandBuilder().build(request: request, azCopyURL: executable))
        }

        func run(arguments: [String], expectSuccess: Bool = true) async throws -> AzCopyRunResult {
            try await execute(AzCopyInvocation(executableURL: executable, arguments: arguments), expectSuccess: expectSuccess)
        }

        func execute(_ invocation: AzCopyInvocation, expectSuccess: Bool = true) async throws -> AzCopyRunResult {
            var isolated = invocation
            isolated.environment.merge([
                "HOME": directory.appendingPathComponent("home").path,
                "AZCOPY_LOG_LOCATION": directory.appendingPathComponent("logs").path,
                "AZCOPY_JOB_PLAN_LOCATION": directory.appendingPathComponent("plans").path,
                "AZCOPY_CONCURRENCY_VALUE": "4",
                "NO_PROXY": "127.0.0.1,localhost"
            ]) { _, value in value }
            let result = try await runner.run(isolated)
            if expectSuccess {
                try #require(result.exitCode == 0, "\(isolated.redactedPreview)\n\(result.output)\n\(result.errorOutput)")
            }
            return result
        }
    }
}
