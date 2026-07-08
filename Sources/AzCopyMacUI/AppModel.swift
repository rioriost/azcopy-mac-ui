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
        didSet { defaults.set(source, forKey: DefaultsKey.source) }
    }
    @Published var destination: String = "" {
        didSet { defaults.set(destination, forKey: DefaultsKey.destination) }
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
        didSet { defaults.set(extraFlagsText, forKey: DefaultsKey.extraFlagsText) }
    }
    @Published var jobID: String = "" {
        didSet { defaults.set(jobID, forKey: DefaultsKey.jobID) }
    }
    @Published var jobTransferStatus: String = "" {
        didSet { defaults.set(jobTransferStatus, forKey: DefaultsKey.jobTransferStatus) }
    }
    @Published var sourceSAS: String = "" {
        didSet {}
    }
    @Published var destinationSAS: String = "" {
        didSet {}
    }
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
    @Published var servicePrincipalSecret: String = "" {
        didSet {}
    }
    @Published var certificatePath: String = "" {
        didSet { defaults.set(certificatePath, forKey: DefaultsKey.certificatePath) }
    }
    @Published var certificatePassword: String = "" {
        didSet {}
    }
    @Published var managedIdentityID: String = "" {
        didSet { defaults.set(managedIdentityID, forKey: DefaultsKey.managedIdentityID) }
    }
    @Published var commandPreview: String = ""
    @Published var statusMessage: String = "Ready"
    @Published var isRunning: Bool = false
    @Published var logText: String = ""
    @Published var tenantOptions: [TenantOption] = []
    @Published var tenantLoadMessage: String = ""

    private let builder = AzCopyCommandBuilder()
    private let runner = AzCopyProcessRunner()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadPersistedValues()
        refreshPreview()
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
        extraFlagsText = defaults.string(forKey: DefaultsKey.extraFlagsText) ?? ""
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
            let invocation = try builder.build(
                request: makeTransferRequest(),
                azCopyURL: URL(fileURLWithPath: effectiveAzCopyPath)
            )
            commandPreview = invocation.redactedPreview
            statusMessage = "Command is ready."
        } catch {
            commandPreview = ""
            statusMessage = error.localizedDescription
        }
    }

    func runSelectedCommand() async {
        guard !isRunning else { return }

        let invocation: AzCopyInvocation
        do {
            invocation = try builder.build(
                request: makeTransferRequest(),
                azCopyURL: URL(fileURLWithPath: effectiveAzCopyPath)
            )
        } catch {
            statusMessage = error.localizedDescription
            appendLog("Validation failed: \(error.localizedDescription)")
            return
        }

        isRunning = true
        statusMessage = "Running..."
        appendLog("$ \(invocation.redactedPreview)")

        do {
            let result = try await runner.run(invocation)
            if !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendLog(result.output)
            }
            if !result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendLog(result.errorOutput)
            }
            statusMessage = result.exitCode == 0 ? "Command succeeded." : "Command failed with exit code \(result.exitCode)."
            appendLog(statusMessage)
        } catch {
            statusMessage = error.localizedDescription
            appendLog("Launch failed: \(error.localizedDescription)")
        }

        isRunning = false
        refreshPreview()
    }

    private func makeTransferRequest() -> TransferRequest {
        let actionNeedsDestination = selectedAction == .copy || selectedAction == .sync
        let overwrite = selectedAction == .copy ? overwriteExisting : nil
        let deleteDestinationValue = selectedAction == .sync ? deleteDestination : nil
        let authentication = selectedAuthentication.method(
            tenantID: tenantID,
            applicationID: applicationID,
            servicePrincipalSecret: servicePrincipalSecret,
            certificatePath: certificatePath,
            certificatePassword: certificatePassword,
            managedIdentityID: managedIdentityID
        )
        return TransferRequest(
            action: selectedAction,
            source: source,
            destination: actionNeedsDestination && !destination.isEmpty ? destination : nil,
            recursive: recursive,
            dryRun: dryRun,
            overwrite: overwrite,
            deleteDestination: deleteDestinationValue,
            extraFlags: extraFlags(),
            authentication: authentication,
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
            showSensitiveEnvironment: showSensitiveEnvironment
        )
    }

    private func appendLog(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .newlines)
        guard !trimmedText.isEmpty else { return }
        if !logText.isEmpty {
            logText += "\n"
        }
        logText += trimmedText
    }

    private var effectiveAzCopyPath: String {
        let trimmedPath = azCopyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPath.isEmpty ? AzCopyLocator.homebrewAppleSiliconPath : trimmedPath
    }

    func loadTenants() {
        tenantLoadMessage = "Loading tenants..."
        Task {
            do {
                let tenants = try await Self.fetchTenants()
                tenantOptions = tenants
                tenantLoadMessage = tenants.isEmpty ? "No tenants returned by Azure CLI." : ""
                if tenantID.isEmpty, let firstTenant = tenants.first {
                    tenantID = firstTenant.id
                    refreshPreview()
                }
            } catch {
                tenantLoadMessage = error.localizedDescription
            }
        }
    }

    private func extraFlags() -> [String] {
        var flags: [String] = []
        let trimmedCapMbps = capMbps.trimmingCharacters(in: .whitespacesAndNewlines)
        if supportsCapMbps, !trimmedCapMbps.isEmpty {
            flags.append("--cap-mbps=\(trimmedCapMbps)")
        }

        if supportsPatternFlags {
            let trimmedIncludePattern = includePattern.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedIncludePattern.isEmpty {
                flags.append("--include-pattern=\(trimmedIncludePattern)")
            }

            let trimmedExcludePattern = excludePattern.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedExcludePattern.isEmpty {
                flags.append("--exclude-pattern=\(trimmedExcludePattern)")
            }
        }

        flags.append(contentsOf: extraFlagsText
            .split(whereSeparator: \.isWhitespace)
            .map(String.init))
        return flags
    }

    private var supportsPatternFlags: Bool {
        switch selectedAction {
        case .copy, .sync, .remove, .setProperties:
            true
        default:
            false
        }
    }

    private var supportsCapMbps: Bool {
        switch selectedAction {
        case .copy, .sync, .bench:
            true
        default:
            false
        }
    }

    private nonisolated static func fetchTenants() async throws -> [TenantOption] {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/az")
            process.arguments = [
                "account",
                "tenant",
                "list",
                "--query",
                "[].{tenantId:tenantId,displayName:displayName}",
                "-o",
                "tsv"
            ]

            let output = Pipe()
            let errorOutput = Pipe()
            process.standardOutput = output
            process.standardError = errorOutput
            try process.run()
            process.waitUntilExit()

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else {
                let message = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw TenantLoadError.azureCLI(message?.isEmpty == false ? message! : "Azure CLI tenant lookup failed.")
            }

            let text = String(data: data, encoding: .utf8) ?? ""
            return text
                .split(separator: "\n")
                .compactMap { line -> TenantOption? in
                    let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                    guard let tenantID = columns.first, !tenantID.isEmpty else { return nil }
                    let name = columns.dropFirst().first?.nilIfPlaceholder
                    return TenantOption(id: tenantID, displayName: name)
                }
        }.value
    }
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
            return .deviceCodeEnvironment
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
