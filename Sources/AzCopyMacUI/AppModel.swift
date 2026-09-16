import AzCopyMacUICore
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var azCopyPath: String = "" {
        didSet {
            if azCopyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                defaults.removeObject(forKey: DefaultsKey.azCopyPath)
            } else {
                defaults.set(azCopyPath, forKey: DefaultsKey.azCopyPath)
            }
        }
    }
    @Published var source: String = "" {
        didSet { persistEndpoint(source, key: DefaultsKey.source) }
    }
    @Published var destination: String = "" {
        didSet { persistEndpoint(destination, key: DefaultsKey.destination) }
    }
    @Published var recursive: Bool = true {
        didSet { defaults.set(recursive, forKey: DefaultsKey.recursive) }
    }
    @Published var dryRun: Bool = false {
        didSet { defaults.set(dryRun, forKey: DefaultsKey.dryRun) }
    }
    @Published var overwriteExisting: Bool = true {
        didSet { defaults.set(overwriteExisting, forKey: DefaultsKey.overwriteExisting) }
    }
    @Published var deleteDestination: Bool = false {
        didSet { defaults.set(deleteDestination, forKey: DefaultsKey.deleteDestination) }
    }
    @Published var capMbps: String = "" {
        didSet { defaults.set(capMbps, forKey: DefaultsKey.capMbps) }
    }
    @Published var includePattern: String = "" {
        didSet { defaults.set(includePattern, forKey: DefaultsKey.includePattern) }
    }
    @Published var excludePattern: String = "" {
        didSet { defaults.set(excludePattern, forKey: DefaultsKey.excludePattern) }
    }
    @Published var extraFlagsText: String = "" {
        didSet { defaults.removeObject(forKey: DefaultsKey.extraFlagsText) }
    }
    @Published var jobID: String = "" {
        didSet { defaults.set(jobID, forKey: DefaultsKey.jobID) }
    }
    @Published var jobTransferStatus: String = "" {
        didSet { defaults.set(jobTransferStatus, forKey: DefaultsKey.jobTransferStatus) }
    }
    @Published var sourceSAS: String = ""
    @Published var destinationSAS: String = ""
    @Published var benchMode: String = "upload" {
        didSet { defaults.set(benchMode, forKey: DefaultsKey.benchMode) }
    }
    @Published var benchFileCount: String = "" {
        didSet { defaults.set(benchFileCount, forKey: DefaultsKey.benchFileCount) }
    }
    @Published var benchSizePerFile: String = "" {
        didSet { defaults.set(benchSizePerFile, forKey: DefaultsKey.benchSizePerFile) }
    }
    @Published var benchNumberOfFolders: String = "" {
        didSet { defaults.set(benchNumberOfFolders, forKey: DefaultsKey.benchNumberOfFolders) }
    }
    @Published var benchDeleteTestData: Bool = true {
        didSet { defaults.set(benchDeleteTestData, forKey: DefaultsKey.benchDeleteTestData) }
    }
    @Published var benchPutMD5: Bool = false {
        didSet { defaults.set(benchPutMD5, forKey: DefaultsKey.benchPutMD5) }
    }
    @Published var benchCheckLength: Bool = true {
        didSet { defaults.set(benchCheckLength, forKey: DefaultsKey.benchCheckLength) }
    }
    @Published var makeQuotaGB: String = "" {
        didSet { defaults.set(makeQuotaGB, forKey: DefaultsKey.makeQuotaGB) }
    }
    @Published var blockBlobTier: String = "None" {
        didSet { defaults.set(blockBlobTier, forKey: DefaultsKey.blockBlobTier) }
    }
    @Published var pageBlobTier: String = "None" {
        didSet { defaults.set(pageBlobTier, forKey: DefaultsKey.pageBlobTier) }
    }
    @Published var rehydratePriority: String = "Standard" {
        didSet { defaults.set(rehydratePriority, forKey: DefaultsKey.rehydratePriority) }
    }
    @Published var metadata: String = "" {
        didSet { defaults.set(metadata, forKey: DefaultsKey.metadata) }
    }
    @Published var blobTags: String = "" {
        didSet { defaults.set(blobTags, forKey: DefaultsKey.blobTags) }
    }
    @Published var includePath: String = "" {
        didSet { defaults.set(includePath, forKey: DefaultsKey.includePath) }
    }
    @Published var excludePath: String = "" {
        didSet { defaults.set(excludePath, forKey: DefaultsKey.excludePath) }
    }
    @Published var listOfFiles: String = "" {
        didSet { defaults.set(listOfFiles, forKey: DefaultsKey.listOfFiles) }
    }
    @Published var showSensitiveEnvironment: Bool = false {
        didSet { defaults.set(showSensitiveEnvironment, forKey: DefaultsKey.showSensitiveEnvironment) }
    }
    @Published var selectedAction: TransferAction = .copy {
        didSet { defaults.set(selectedAction.rawValue, forKey: DefaultsKey.selectedAction) }
    }
    @Published var selectedAuthentication: AuthenticationOption = .userIdentity {
        didSet { defaults.set(selectedAuthentication.rawValue, forKey: DefaultsKey.selectedAuthentication) }
    }
    @Published var tenantID: String = "" {
        didSet { defaults.set(tenantID, forKey: DefaultsKey.tenantID) }
    }
    @Published var applicationID: String = "" {
        didSet { defaults.set(applicationID, forKey: DefaultsKey.applicationID) }
    }
    @Published var servicePrincipalSecret: String = ""
    @Published var certificatePath: String = "" {
        didSet { defaults.set(certificatePath, forKey: DefaultsKey.certificatePath) }
    }
    @Published var certificatePassword: String = ""
    @Published var managedIdentityID: String = "" {
        didSet { defaults.set(managedIdentityID, forKey: DefaultsKey.managedIdentityID) }
    }
    @Published var commandPreview: String = ""
    @Published private(set) var validationMessage: String = ""
    @Published private(set) var executionState: CommandExecutionState = .idle
    @Published private(set) var activeCommandPreview: String = ""
    @Published private(set) var logText: String = ""
    @Published private(set) var settingsNotice: String = ""
    @Published var pendingCommand: PendingCommand?
    @Published var tenantOptions: [TenantOption] = []
    @Published var tenantLoadMessage: String = ""
    @Published private(set) var isLoadingTenants = false

    private let builder = AzCopyCommandBuilder()
    private let runner: any AzCopyRunning
    private let defaults: UserDefaults
    private var runningTask: Task<Void, Never>?
    private var tenantTask: Task<Void, Never>?
    static let logCharacterLimit = 128 * 1024

    var isRunning: Bool { executionState == .running }
    var statusMessage: String { executionState.message }

    init(defaults: UserDefaults = .standard, runner: any AzCopyRunning = AzCopyProcessRunner()) {
        self.defaults = defaults
        self.runner = runner
        migratePreferences()
        loadPersistedValues()
        refreshPreview()
    }

    private func migratePreferences() {
        var removedCredentials = false
        for key in [DefaultsKey.source, DefaultsKey.destination] {
            if let value = defaults.string(forKey: key) {
                let safeValue = Self.persistableEndpoint(value)
                if safeValue != value {
                    removedCredentials = true
                    defaults.set(safeValue, forKey: key)
                }
            }
        }
        if let flags = defaults.string(forKey: DefaultsKey.extraFlagsText), !flags.isEmpty {
            removedCredentials = true
        }
        defaults.removeObject(forKey: DefaultsKey.extraFlagsText)
        for key in ["sourceSAS", "destinationSAS", "servicePrincipalSecret", "certificatePassword"] {
            if defaults.object(forKey: key) != nil {
                removedCredentials = true
                defaults.removeObject(forKey: key)
            }
        }
        if removedCredentials {
            settingsNotice = "Saved URL credentials and additional flags were removed. Re-enter credentials before running."
        }
        if defaults.string(forKey: DefaultsKey.selectedAuthentication) == AuthenticationOption.managedIdentityObjectID.rawValue {
            settingsNotice += (settingsNotice.isEmpty ? "" : "\n") +
                "Managed identity object ID is no longer supported. Select a client ID or resource ID; the saved ID has not been converted."
        }
    }

    private static func persistableEndpoint(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("://") || trimmed.lowercased().hasPrefix("https:") ||
                trimmed.lowercased().hasPrefix("http:") else { return value }
        guard var components = URLComponents(string: trimmed), components.host?.isEmpty == false else {
            return nil
        }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.string
    }

    private func persistEndpoint(_ value: String, key: String) {
        defaults.set(Self.persistableEndpoint(value), forKey: key)
    }

    private func loadPersistedValues() {
        if let storedAzCopyPath = defaults.string(forKey: DefaultsKey.azCopyPath),
           storedAzCopyPath != AzCopyLocator.homebrewAppleSiliconPath {
            azCopyPath = storedAzCopyPath
        } else {
            azCopyPath = ""
            defaults.removeObject(forKey: DefaultsKey.azCopyPath)
        }
        source = defaults.string(forKey: DefaultsKey.source) ?? ""
        destination = defaults.string(forKey: DefaultsKey.destination) ?? ""
        recursive = defaults.object(forKey: DefaultsKey.recursive) as? Bool ?? true
        dryRun = defaults.object(forKey: DefaultsKey.dryRun) as? Bool ?? false
        overwriteExisting = defaults.object(forKey: DefaultsKey.overwriteExisting) as? Bool ?? true
        deleteDestination = defaults.object(forKey: DefaultsKey.deleteDestination) as? Bool ?? false
        capMbps = defaults.string(forKey: DefaultsKey.capMbps) ?? ""
        includePattern = defaults.string(forKey: DefaultsKey.includePattern) ?? ""
        excludePattern = defaults.string(forKey: DefaultsKey.excludePattern) ?? ""
        extraFlagsText = ""
        jobID = defaults.string(forKey: DefaultsKey.jobID) ?? ""
        jobTransferStatus = defaults.string(forKey: DefaultsKey.jobTransferStatus) ?? ""
        sourceSAS = ""
        destinationSAS = ""
        benchMode = defaults.string(forKey: DefaultsKey.benchMode) ?? "upload"
        benchFileCount = defaults.string(forKey: DefaultsKey.benchFileCount) ?? ""
        benchSizePerFile = defaults.string(forKey: DefaultsKey.benchSizePerFile) ?? ""
        benchNumberOfFolders = defaults.string(forKey: DefaultsKey.benchNumberOfFolders) ?? ""
        benchDeleteTestData = defaults.object(forKey: DefaultsKey.benchDeleteTestData) as? Bool ?? true
        benchPutMD5 = defaults.object(forKey: DefaultsKey.benchPutMD5) as? Bool ?? false
        benchCheckLength = defaults.object(forKey: DefaultsKey.benchCheckLength) as? Bool ?? true
        makeQuotaGB = defaults.string(forKey: DefaultsKey.makeQuotaGB) ?? ""
        blockBlobTier = defaults.string(forKey: DefaultsKey.blockBlobTier) ?? "None"
        pageBlobTier = defaults.string(forKey: DefaultsKey.pageBlobTier) ?? "None"
        rehydratePriority = defaults.string(forKey: DefaultsKey.rehydratePriority) ?? "Standard"
        metadata = defaults.string(forKey: DefaultsKey.metadata) ?? ""
        blobTags = defaults.string(forKey: DefaultsKey.blobTags) ?? ""
        includePath = defaults.string(forKey: DefaultsKey.includePath) ?? ""
        excludePath = defaults.string(forKey: DefaultsKey.excludePath) ?? ""
        listOfFiles = defaults.string(forKey: DefaultsKey.listOfFiles) ?? ""
        showSensitiveEnvironment = defaults.object(forKey: DefaultsKey.showSensitiveEnvironment) as? Bool ?? false

        if let rawAction = defaults.string(forKey: DefaultsKey.selectedAction),
           let action = TransferAction(rawValue: rawAction) {
            selectedAction = action
        }

        if let rawAuthentication = defaults.string(forKey: DefaultsKey.selectedAuthentication),
           let authentication = AuthenticationOption(rawValue: rawAuthentication) {
            selectedAuthentication = authentication
        }

        tenantID = defaults.string(forKey: DefaultsKey.tenantID) ?? ""
        applicationID = defaults.string(forKey: DefaultsKey.applicationID) ?? ""
        servicePrincipalSecret = ""
        certificatePath = defaults.string(forKey: DefaultsKey.certificatePath) ?? ""
        certificatePassword = ""
        managedIdentityID = defaults.string(forKey: DefaultsKey.managedIdentityID) ?? ""
    }

    func refreshPreview() {
        do {
            let invocation = try buildInvocation()
            commandPreview = invocation.redactedPreview
            validationMessage = ""
        } catch {
            commandPreview = ""
            validationMessage = CredentialRedactor.redact(error.localizedDescription)
        }
    }

    func runSelectedCommand() {
        guard !isRunning, pendingCommand == nil else { return }
        do {
            let request = try makeTransferRequest()
            let invocation = try buildInvocation(request: request)
            if Self.requiresConfirmation(request) {
                pendingCommand = PendingCommand(invocation: invocation)
            } else {
                start(invocation)
            }
        } catch {
            executionState = .failed(CredentialRedactor.redact(error.localizedDescription))
            appendLog("Validation failed: \(error.localizedDescription)")
        }
    }

    func confirmPendingCommand(_ command: PendingCommand) {
        guard !isRunning else { return }
        pendingCommand = nil
        start(command.invocation)
    }

    func signIn() {
        guard !isRunning, pendingCommand == nil else { return }
        do {
            let invocation = try builder.buildLogin(
                method: authenticationMethod,
                azCopyURL: URL(fileURLWithPath: effectiveAzCopyPath)
            )
            try SecurityPolicy().validate(invocation: invocation)
            start(invocation)
        } catch {
            executionState = .failed(CredentialRedactor.redact(error.localizedDescription))
            appendLog("Sign in failed: \(error.localizedDescription)")
        }
    }

    func cancelCommand() {
        runningTask?.cancel()
    }

    func cancelTenantLookup() {
        tenantTask?.cancel()
    }

    func waitForCommand() async {
        await runningTask?.value
    }

    func waitForTenantLookup() async {
        await tenantTask?.value
    }

    private func start(_ invocation: AzCopyInvocation) {
        executionState = .running
        activeCommandPreview = invocation.redactedPreview
        appendLog("$ \(invocation.redactedPreview)")
        runningTask = Task { [weak self, runner] in
            do {
                let result = try await runner.run(invocation) { [weak self] event in
                    await self?.appendOutput(event.text)
                }
                try Task.checkCancellation()
                self?.executionState = result.exitCode == 0
                    ? .succeeded : .failed("Command failed with exit code \(result.exitCode).")
            } catch is CancellationError {
                self?.executionState = .cancelled
            } catch {
                self?.executionState = .failed(CredentialRedactor.redact(error.localizedDescription))
            }
            if let self {
                self.appendLog(self.statusMessage)
                self.runningTask = nil
            }
        }
    }

    private func buildInvocation(request: TransferRequest? = nil) throws -> AzCopyInvocation {
        let invocation = try builder.build(
            request: try request ?? makeTransferRequest(),
            azCopyURL: URL(fileURLWithPath: effectiveAzCopyPath)
        )
        try SecurityPolicy().validate(invocation: invocation)
        return invocation
    }

    private static func requiresConfirmation(_ request: TransferRequest) -> Bool {
        switch request.action {
        case .remove:
            !request.dryRun
        case .sync:
            request.deleteDestination == true && !request.dryRun
        case .jobsRemove, .jobsClean:
            true
        default:
            false
        }
    }

    private var authenticationMethod: AuthenticationMethod {
        selectedAuthentication.method(
            tenantID: tenantID,
            applicationID: applicationID,
            servicePrincipalSecret: servicePrincipalSecret,
            certificatePath: certificatePath,
            certificatePassword: certificatePassword,
            managedIdentityID: managedIdentityID
        )
    }

    private func makeTransferRequest() throws -> TransferRequest {
        let actionNeedsDestination = selectedAction == .copy || selectedAction == .sync
        let overwrite = selectedAction == .copy ? overwriteExisting : nil
        let deleteDestinationValue = selectedAction == .sync ? deleteDestination : nil
        return TransferRequest(
            action: selectedAction,
            source: source,
            destination: actionNeedsDestination && !destination.isEmpty ? destination : nil,
            recursive: recursive,
            dryRun: dryRun,
            overwrite: overwrite,
            deleteDestination: deleteDestinationValue,
            extraFlags: try ExtraFlagsParser.parse(extraFlagsText),
            authentication: authenticationMethod,
            jobID: jobID,
            jobTransferStatus: jobTransferStatus,
            sourceSAS: sourceSAS,
            destinationSAS: destinationSAS,
            benchMode: benchMode,
            benchFileCount: benchFileCount,
            benchSizePerFile: benchSizePerFile,
            benchNumberOfFolders: benchNumberOfFolders,
            benchDeleteTestData: benchDeleteTestData,
            benchPutMD5: benchPutMD5,
            benchCheckLength: benchCheckLength,
            makeQuotaGB: makeQuotaGB,
            blockBlobTier: blockBlobTier,
            pageBlobTier: pageBlobTier,
            rehydratePriority: rehydratePriority,
            metadata: metadata,
            blobTags: blobTags,
            includePath: includePath,
            excludePath: excludePath,
            listOfFiles: listOfFiles,
            showSensitiveEnvironment: showSensitiveEnvironment,
            capMbps: capMbps,
            includePattern: includePattern,
            excludePattern: excludePattern
        )
    }

    private func appendLog(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .newlines)
        guard !trimmedText.isEmpty else { return }
        if !logText.isEmpty, !logText.hasSuffix("\n") {
            logText += "\n"
        }
        appendOutput(CredentialRedactor.redact(trimmedText) + "\n")
    }

    private func appendOutput(_ text: String) {
        logText += text.replacingOccurrences(of: "\r", with: "\n")
        if logText.count > Self.logCharacterLimit {
            let marker = "[Earlier output truncated]\n"
            logText = marker + logText.suffix(Self.logCharacterLimit - marker.count)
        }
    }

    private var effectiveAzCopyPath: String {
        let trimmedPath = azCopyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPath.isEmpty ? AzCopyLocator.homebrewAppleSiliconPath : trimmedPath
    }

    func loadTenants() {
        guard !isLoadingTenants else { return }
        isLoadingTenants = true
        tenantLoadMessage = "Loading tenants..."
        tenantTask = Task {
            defer {
                isLoadingTenants = false
                tenantTask = nil
            }
            do {
                let tenants = try await Self.fetchTenants(runner: runner)
                tenantOptions = tenants
                tenantLoadMessage = tenants.isEmpty ? "No tenants returned by Azure CLI." : ""
                if tenantID.isEmpty, let firstTenant = tenants.first {
                    tenantID = firstTenant.id
                    refreshPreview()
                }
            } catch is CancellationError {
                tenantLoadMessage = "Tenant lookup cancelled."
            } catch {
                tenantLoadMessage = CredentialRedactor.redact(error.localizedDescription)
            }
        }
    }

    private nonisolated static func fetchTenants(runner: any AzCopyRunning) async throws -> [TenantOption] {
        let invocation = AzCopyInvocation(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/az"),
            arguments: [
                "account",
                "tenant",
                "list",
                "--query",
                "[].{tenantId:tenantId,displayName:displayName}",
                "-o",
                "tsv"
            ])
        let result = try await runner.run(invocation) { _ in }
        guard result.exitCode == 0 else {
            let message = result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TenantLoadError.azureCLI(message.isEmpty ? "Azure CLI tenant lookup failed." : message)
        }
        guard !result.outputTruncated else {
            throw TenantLoadError.azureCLI("Azure CLI tenant output was truncated. Narrow the tenant lookup before retrying.")
        }
        return try result.output.split(separator: "\n").map { line in
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count == 2, !columns[0].isEmpty else {
                throw TenantLoadError.azureCLI("Azure CLI returned an invalid tenant list.")
            }
            return TenantOption(id: columns[0], displayName: columns[1].nilIfPlaceholder)
        }
    }
}

enum CommandExecutionState: Equatable {
    case idle
    case running
    case succeeded
    case failed(String)
    case cancelled

    var message: String {
        switch self {
        case .idle: "Ready"
        case .running: "Running..."
        case .succeeded: "Command succeeded."
        case .failed(let message): message
        case .cancelled: "Command cancelled."
        }
    }
}

struct PendingCommand: Identifiable {
    let id = UUID()
    let invocation: AzCopyInvocation
    var preview: String { invocation.redactedPreview }
}

struct TenantOption: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String?

    var title: String {
        if let displayName, !displayName.isEmpty {
            "\(displayName) (\(id))"
        } else {
            id
        }
    }
}

private enum TenantLoadError: LocalizedError {
    case azureCLI(String)

    var errorDescription: String? {
        switch self {
        case .azureCLI(let message):
            message
        }
    }
}

private extension String {
    var nilIfPlaceholder: String? {
        self == "None" ? nil : self
    }
}

private enum DefaultsKey {
    static let azCopyPath = "azCopyPath"
    static let source = "source"
    static let destination = "destination"
    static let recursive = "recursive"
    static let dryRun = "dryRun"
    static let overwriteExisting = "overwriteExisting"
    static let deleteDestination = "deleteDestination"
    static let capMbps = "capMbps"
    static let includePattern = "includePattern"
    static let excludePattern = "excludePattern"
    static let extraFlagsText = "extraFlagsText"
    static let jobID = "jobID"
    static let jobTransferStatus = "jobTransferStatus"
    static let benchMode = "benchMode"
    static let benchFileCount = "benchFileCount"
    static let benchSizePerFile = "benchSizePerFile"
    static let benchNumberOfFolders = "benchNumberOfFolders"
    static let benchDeleteTestData = "benchDeleteTestData"
    static let benchPutMD5 = "benchPutMD5"
    static let benchCheckLength = "benchCheckLength"
    static let makeQuotaGB = "makeQuotaGB"
    static let blockBlobTier = "blockBlobTier"
    static let pageBlobTier = "pageBlobTier"
    static let rehydratePriority = "rehydratePriority"
    static let metadata = "metadata"
    static let blobTags = "blobTags"
    static let includePath = "includePath"
    static let excludePath = "excludePath"
    static let listOfFiles = "listOfFiles"
    static let showSensitiveEnvironment = "showSensitiveEnvironment"
    static let selectedAction = "selectedAction"
    static let selectedAuthentication = "selectedAuthentication"
    static let tenantID = "tenantID"
    static let applicationID = "applicationID"
    static let certificatePath = "certificatePath"
    static let managedIdentityID = "managedIdentityID"
}

enum AuthenticationOption: String, CaseIterable, Identifiable {
    case userIdentity
    case deviceCode
    case azureCLI
    case azurePowerShell
    case servicePrincipalSecret
    case servicePrincipalCertificate
    case managedIdentitySystem
    case managedIdentityClientID
    case managedIdentityObjectID
    case managedIdentityResourceID
    case sas

    var id: String { rawValue }

    var supportsSignIn: Bool {
        switch self {
        case .userIdentity, .deviceCode, .servicePrincipalSecret, .servicePrincipalCertificate,
             .managedIdentitySystem, .managedIdentityClientID, .managedIdentityResourceID:
            true
        default:
            false
        }
    }

    var title: String {
        method(
            tenantID: nil,
            applicationID: "",
            servicePrincipalSecret: "",
            certificatePath: "",
            certificatePassword: "",
            managedIdentityID: ""
        ).displayName
    }

    func method(
        tenantID: String?,
        applicationID: String,
        servicePrincipalSecret: String,
        certificatePath: String,
        certificatePassword: String,
        managedIdentityID: String
    ) -> AuthenticationMethod {
        let normalizedTenantID = tenantID?.isEmpty == true ? nil : tenantID
        switch self {
        case .userIdentity:
            return .userIdentity(tenantID: normalizedTenantID)
        case .deviceCode:
            return .deviceCode(tenantID: normalizedTenantID)
        case .azureCLI:
            return .azureCLI(tenantID: normalizedTenantID)
        case .azurePowerShell:
            return .azurePowerShell(tenantID: normalizedTenantID)
        case .servicePrincipalSecret:
            return .servicePrincipalSecret(
                applicationID: applicationID,
                tenantID: normalizedTenantID ?? "",
                clientSecret: servicePrincipalSecret
            )
        case .servicePrincipalCertificate:
            return .servicePrincipalCertificate(
                applicationID: applicationID,
                tenantID: normalizedTenantID ?? "",
                certificatePath: certificatePath,
                certificatePassword: certificatePassword.isEmpty ? nil : certificatePassword
            )
        case .managedIdentitySystem:
            return .managedIdentitySystem
        case .managedIdentityClientID:
            return .managedIdentityClientID(managedIdentityID)
        case .managedIdentityObjectID:
            return .managedIdentityObjectID(managedIdentityID)
        case .managedIdentityResourceID:
            return .managedIdentityResourceID(managedIdentityID)
        case .sas:
            return .sas
        }
    }
}
