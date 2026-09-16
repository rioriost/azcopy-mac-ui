import AzCopyMacUICore
import Foundation
import Testing
@testable import AzCopyMacUIModel

@Suite("AppModel")
@MainActor
struct AppModelTests {
    @Test("URL credentials and additional flags are never persisted")
    func credentialsStayInMemory() throws {
        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.source = "https://user:password@example.blob.core.windows.net/source?sv=1&sig=SOURCE_SECRET#token"
        model.destination = "https://example.dfs.core.windows.net/destination?sig=DESTINATION_SECRET"
        model.extraFlagsText = "--source-sas sv=1&sig=FLAG_SECRET"
        model.servicePrincipalSecret = "CLIENT_SECRET"
        model.certificatePassword = "CERT_PASSWORD"
        model.sourceSAS = "SOURCE_SAS"
        model.destinationSAS = "DESTINATION_SAS"

        #expect(defaults.string(forKey: "source") == "https://example.blob.core.windows.net/source")
        #expect(defaults.string(forKey: "destination") == "https://example.dfs.core.windows.net/destination")
        for key in ["extraFlagsText", "sourceSAS", "destinationSAS", "servicePrincipalSecret", "certificatePassword"] {
            #expect(defaults.object(forKey: key) == nil)
        }
        #expect(model.source.contains("SOURCE_SECRET"))
        model.selectedAuthentication = .sas
        model.extraFlagsText = ""
        model.refreshPreview()
        #expect(!model.commandPreview.contains("password"))
        #expect(!model.commandPreview.contains("user:"))
        #expect(!model.commandPreview.contains("SOURCE_SECRET"))
        let restored = AppModel(defaults: defaults)
        #expect(!restored.source.contains("SECRET"))
        #expect(restored.extraFlagsText.isEmpty)
        #expect(restored.servicePrincipalSecret.isEmpty)
    }

    @Test("legacy credentials are removed before settings are restored")
    func migratesLegacySecrets() throws {
        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("HTTPS://example.blob.core.windows.net/data?sig=LEGACY_SECRET", forKey: "source")
        defaults.set("--destination-sas=LEGACY_SECRET", forKey: "extraFlagsText")
        defaults.set("LEGACY_SECRET", forKey: "certificatePassword")
        defaults.set("managedIdentityObjectID", forKey: "selectedAuthentication")
        defaults.set("old-object-id", forKey: "managedIdentityID")

        let model = AppModel(defaults: defaults)
        #expect(!model.source.contains("LEGACY_SECRET"))
        #expect(model.extraFlagsText.isEmpty)
        #expect(defaults.object(forKey: "certificatePassword") == nil)
        #expect(model.settingsNotice.contains("Re-enter"))
        #expect(model.settingsNotice.contains("object ID"))
        #expect(!model.settingsNotice.contains("LEGACY_SECRET"))
        #expect(model.selectedAuthentication == .managedIdentityObjectID)
        #expect(model.managedIdentityID == "old-object-id")
    }

    @Test("nonsecret local paths and options still persist")
    func retainsNonsecretPreferences() throws {
        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.source = "/tmp/folder with spaces"
        model.destination = "/tmp/output"
        model.recursive = false
        model.capMbps = "25"
        let restored = AppModel(defaults: defaults)
        #expect(restored.source == model.source)
        #expect(restored.destination == model.destination)
        #expect(!restored.recursive)
        #expect(restored.capMbps == "25")
        model.source = "https://[malformed?sig=SECRET"
        #expect(defaults.object(forKey: "source") == nil)
    }

    @Test("failure survives preview changes")
    func failureIsRetained() async throws {
        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runner = RecordingRunner(exitCode: 7)
        let model = AppModel(defaults: defaults, runner: runner)
        model.selectedAction = .env
        model.runSelectedCommand()
        await model.waitForCommand()
        #expect(model.executionState == .failed("Command failed with exit code 7."))
        #expect(model.logText.contains("exit code 7"))
        model.refreshPreview()
        #expect(model.statusMessage.contains("exit code 7"))
        #expect(!model.commandPreview.isEmpty)
    }

    @Test("output is visible before completion and cancellation is not success")
    func cancellationAndStreaming() async throws {
        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runner = RecordingRunner(output: "Device code: EXAMPLE\n", waitsForCancellation: true)
        let model = AppModel(defaults: defaults, runner: runner)
        model.selectedAction = .env
        model.runSelectedCommand()
        await runner.waitForOutput()
        #expect(model.isRunning)
        #expect(model.logText.contains("Device code: EXAMPLE"))
        let snapshot = model.activeCommandPreview
        model.selectedAction = .jobsClean
        model.refreshPreview()
        #expect(model.activeCommandPreview == snapshot)
        model.runSelectedCommand()
        #expect(await runner.invocations.count == 1)
        model.cancelCommand()
        await model.waitForCommand()
        #expect(model.executionState == .cancelled)
        #expect(!model.isRunning)
    }

    @Test("confirmation runs the reviewed snapshot, not the edited form")
    func confirmsSnapshot() async throws {
        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runner = RecordingRunner()
        let model = AppModel(defaults: defaults, runner: runner)
        model.selectedAction = .remove
        model.selectedAuthentication = .sas
        model.source = "https://example.blob.core.windows.net/confirmed?sig=DUMMY"
        model.runSelectedCommand()
        let command = try #require(model.pendingCommand)
        #expect(await runner.invocations.isEmpty)
        #expect(!command.preview.contains("DUMMY"))
        model.source = "https://example.blob.core.windows.net/other"
        model.selectedAction = .jobsClean
        model.confirmPendingCommand(command)
        await model.waitForCommand()
        let invocation = try #require(await runner.invocations.first)
        #expect(invocation.arguments.first == "remove")
        #expect(invocation.arguments[1].contains("/confirmed?"))
        #expect(model.pendingCommand == nil)
    }

    @Test("dry run needs no destructive confirmation and cannot be overridden")
    func enforcesDryRun() async throws {
        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runner = RecordingRunner()
        let model = AppModel(defaults: defaults, runner: runner)
        model.selectedAction = .remove
        model.selectedAuthentication = .sas
        model.source = "https://example.blob.core.windows.net/data"
        model.dryRun = true
        model.extraFlagsText = "--dry-run=false"
        model.refreshPreview()
        #expect(model.commandPreview.isEmpty)
        model.runSelectedCommand()
        #expect(await runner.invocations.isEmpty)
        #expect(model.pendingCommand == nil)
        model.extraFlagsText = ""
        model.runSelectedCommand()
        await model.waitForCommand()
        #expect(model.executionState == .succeeded)
        #expect(model.pendingCommand == nil)
    }

    @Test("sign in is reachable without transfer fields and keeps the selected tenant")
    func signsIn() async throws {
        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runner = RecordingRunner()
        let model = AppModel(defaults: defaults, runner: runner)
        model.tenantID = "selected-tenant"
        model.signIn()
        await model.waitForCommand()
        let invocation = try #require(await runner.invocations.first)
        #expect(invocation.arguments.first == "login")
        #expect(invocation.arguments.contains("--tenant-id=selected-tenant"))
        #expect(model.executionState == .succeeded)
    }

    @Test("typed GUI options do not conflict with reserved additional flags")
    func passesTypedOptions() async throws {
        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runner = RecordingRunner()
        let model = AppModel(defaults: defaults, runner: runner)
        model.source = "/tmp/source"
        model.destination = "https://example.blob.core.windows.net/data"
        model.selectedAuthentication = .deviceCode
        model.tenantID = "tenant-for-device"
        model.capMbps = "10"
        model.includePattern = "*.txt"
        model.excludePattern = "*.tmp"
        model.runSelectedCommand()
        await model.waitForCommand()
        let invocation = try #require(await runner.invocations.first)
        #expect(invocation.arguments.contains("--cap-mbps=10"))
        #expect(invocation.arguments.contains("--include-pattern=*.txt"))
        #expect(invocation.arguments.contains("--exclude-pattern=*.tmp"))
        #expect(invocation.environment["AZCOPY_TENANT_ID"] == "tenant-for-device")
        #expect(invocation.environment["AZCOPY_AUTO_LOGIN_TYPE"] == "DEVICE")
        model.signIn()
        await model.waitForCommand()
        let login = try #require(await runner.invocations.last)
        #expect(login.arguments.first == "login")
        #expect(login.arguments.contains("--tenant-id=tenant-for-device"))
    }

    @Test("quoted additional values remain one argument")
    func preservesArgumentBoundaries() async throws {
        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runner = RecordingRunner()
        let model = AppModel(defaults: defaults, runner: runner)
        model.selectedAction = .env
        model.extraFlagsText = "--log-location=\"/tmp/log folder\""
        model.runSelectedCommand()
        await model.waitForCommand()
        let invocation = try #require(await runner.invocations.first)
        #expect(invocation.arguments.contains("--log-location=/tmp/log folder"))
    }

    @Test("logs have a bounded size and a visible truncation marker")
    func boundsLogs() async throws {
        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runner = RecordingRunner(output: String(repeating: "x", count: AppModel.logCharacterLimit * 2))
        let model = AppModel(defaults: defaults, runner: runner)
        model.selectedAction = .env
        model.runSelectedCommand()
        await model.waitForCommand()
        #expect(model.logText.count <= AppModel.logCharacterLimit)
        #expect(model.logText.hasPrefix("[Earlier output truncated]"))
    }

    @Test("tenant lookup uses the asynchronous runner")
    func loadsTenants() async throws {
        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runner = RecordingRunner(output: "tenant-one\tOne\ntenant-two\tNone\n")
        let model = AppModel(defaults: defaults, runner: runner)
        model.loadTenants()
        await model.waitForTenantLookup()
        #expect(model.tenantOptions.count == 2)
        #expect(model.tenantOptions.last?.displayName == nil)
        #expect(model.tenantID == "tenant-one")
        #expect(!model.isLoadingTenants)
        let invocation = try #require(await runner.invocations.first)
        #expect(invocation.executableURL.path == "/opt/homebrew/bin/az")
    }

    @Test("nonrecursive destructive sync explicitly limits the confirmed command")
    func nonrecursiveSync() async throws {
        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runner = RecordingRunner()
        let model = AppModel(defaults: defaults, runner: runner)
        model.selectedAction = .sync
        model.selectedAuthentication = .sas
        model.source = "/tmp/source"
        model.destination = "https://example.blob.core.windows.net/data"
        model.recursive = false
        model.deleteDestination = true
        model.runSelectedCommand()
        let command = try #require(model.pendingCommand)
        #expect(command.invocation.arguments.contains("--recursive=false"))
        #expect(command.invocation.arguments.contains("--delete-destination=true"))
        model.pendingCommand = nil
        #expect(await runner.invocations.isEmpty)
    }

    @Test("unsupported authentication and insecure URLs fail before launch")
    func rejectsInvalidConfiguration() async throws {
        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runner = RecordingRunner()
        let model = AppModel(defaults: defaults, runner: runner)
        model.selectedAction = .list
        model.source = "http://EXAMPLE.DFS.CORE.WINDOWS.NET/data?sig=DUMMY_SECRET"
        model.selectedAuthentication = .sas
        model.refreshPreview()
        #expect(model.commandPreview.isEmpty)
        #expect(!model.validationMessage.contains("DUMMY_SECRET"))
        model.runSelectedCommand()
        #expect(await runner.invocations.isEmpty)
        #expect(!model.logText.contains("DUMMY_SECRET"))
        model.source = "https://example.blob.core.windows.net/data"
        model.selectedAuthentication = .managedIdentityObjectID
        model.managedIdentityID = "old-object-id"
        model.runSelectedCommand()
        #expect(await runner.invocations.isEmpty)
        #expect(model.statusMessage.lowercased().contains("object"))
    }

    @Test("launch errors and invalid tenant output remain visible")
    func launchAndTenantErrors() async throws {
        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runner = RecordingRunner(failsLaunch: true)
        let model = AppModel(defaults: defaults, runner: runner)
        model.selectedAction = .env
        model.runSelectedCommand()
        await model.waitForCommand()
        #expect(model.statusMessage.contains("Synthetic launch failure"))
        model.refreshPreview()
        #expect(model.statusMessage.contains("Synthetic launch failure"))

        let malformedRunner = RecordingRunner(output: "not a tenant list\n")
        let tenantModel = AppModel(defaults: defaults, runner: malformedRunner)
        tenantModel.loadTenants()
        await tenantModel.waitForTenantLookup()
        #expect(tenantModel.tenantOptions.isEmpty)
        #expect(tenantModel.tenantLoadMessage.contains("invalid tenant list"))
    }

    @Test("tenant lookup rejects truncated structured output")
    func rejectsTruncatedTenantList() async throws {
        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runner = RecordingRunner(output: "tenant-one\tOne\n", outputTruncated: true)
        let model = AppModel(defaults: defaults, runner: runner)
        model.loadTenants()
        await model.waitForTenantLookup()
        #expect(model.tenantOptions.isEmpty)
        #expect(model.tenantID.isEmpty)
        #expect(model.tenantLoadMessage.contains("truncated"))
    }
}

private actor RecordingRunner: AzCopyRunning {
    private(set) var invocations: [AzCopyInvocation] = []
    private let exitCode: Int32
    private let output: String
    private let waitsForCancellation: Bool
    private let failsLaunch: Bool
    private let outputTruncated: Bool
    private var outputDelivered = false
    private var outputWaiters: [CheckedContinuation<Void, Never>] = []

    init(exitCode: Int32 = 0, output: String = "fixture output\n", waitsForCancellation: Bool = false, failsLaunch: Bool = false, outputTruncated: Bool = false) {
        self.exitCode = exitCode
        self.output = output
        self.waitsForCancellation = waitsForCancellation
        self.failsLaunch = failsLaunch
        self.outputTruncated = outputTruncated
    }

    func run(
        _ invocation: AzCopyInvocation,
        onOutput: @escaping @Sendable (AzCopyOutputEvent) async -> Void
    ) async throws -> AzCopyRunResult {
        invocations.append(invocation)
        if failsLaunch { throw AzCopyProcessRunner.RunnerError.launchFailed("Synthetic launch failure") }
        await onOutput(AzCopyOutputEvent(stream: .standardOutput, text: output))
        outputDelivered = true
        for waiter in outputWaiters { waiter.resume() }
        outputWaiters.removeAll()
        if waitsForCancellation {
            try await Task.sleep(for: .seconds(30))
        }
        return AzCopyRunResult(exitCode: exitCode, output: output, errorOutput: "", outputTruncated: outputTruncated)
    }

    func waitForOutput() async {
        if outputDelivered { return }
        await withCheckedContinuation { outputWaiters.append($0) }
    }
}
