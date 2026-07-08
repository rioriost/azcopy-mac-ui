import Foundation

public enum TransferAction: String, CaseIterable, Sendable {
    case copy
    case sync
    case list
    case remove
    case bench
    case make
    case setProperties
    case env
    case jobsList
    case jobsShow
    case jobsResume
    case jobsRemove
    case jobsClean
    case loginStatus
    case logout
}

public struct TransferRequest: Equatable, Sendable {
    public var action: TransferAction
    public var source: String
    public var destination: String?
    public var recursive: Bool
    public var dryRun: Bool
    public var overwrite: Bool?
    public var deleteDestination: Bool?
    public var extraFlags: [String]
    public var authentication: AuthenticationMethod
    public var jobID: String
    public var jobTransferStatus: String
    public var sourceSAS: String
    public var destinationSAS: String
    public var benchMode: String
    public var benchFileCount: String
    public var benchSizePerFile: String
    public var benchNumberOfFolders: String
    public var benchDeleteTestData: Bool
    public var benchPutMD5: Bool
    public var benchCheckLength: Bool
    public var makeQuotaGB: String
    public var blockBlobTier: String
    public var pageBlobTier: String
    public var rehydratePriority: String
    public var metadata: String
    public var blobTags: String
    public var includePath: String
    public var excludePath: String
    public var listOfFiles: String
    public var showSensitiveEnvironment: Bool

    public init(
        action: TransferAction,
        source: String = "",
        destination: String? = nil,
        recursive: Bool = false,
        dryRun: Bool = false,
        overwrite: Bool? = nil,
        deleteDestination: Bool? = nil,
        extraFlags: [String] = [],
        authentication: AuthenticationMethod = .userIdentity(tenantID: nil),
        jobID: String = "",
        jobTransferStatus: String = "",
        sourceSAS: String = "",
        destinationSAS: String = "",
        benchMode: String = "upload",
        benchFileCount: String = "",
        benchSizePerFile: String = "",
        benchNumberOfFolders: String = "",
        benchDeleteTestData: Bool = true,
        benchPutMD5: Bool = false,
        benchCheckLength: Bool = true,
        makeQuotaGB: String = "",
        blockBlobTier: String = "None",
        pageBlobTier: String = "None",
        rehydratePriority: String = "Standard",
        metadata: String = "",
        blobTags: String = "",
        includePath: String = "",
        excludePath: String = "",
        listOfFiles: String = "",
        showSensitiveEnvironment: Bool = false
    ) {
        self.action = action
        self.source = source
        self.destination = destination
        self.recursive = recursive
        self.dryRun = dryRun
        self.overwrite = overwrite
        self.deleteDestination = deleteDestination
        self.extraFlags = extraFlags
        self.authentication = authentication
        self.jobID = jobID
        self.jobTransferStatus = jobTransferStatus
        self.sourceSAS = sourceSAS
        self.destinationSAS = destinationSAS
        self.benchMode = benchMode
        self.benchFileCount = benchFileCount
        self.benchSizePerFile = benchSizePerFile
        self.benchNumberOfFolders = benchNumberOfFolders
        self.benchDeleteTestData = benchDeleteTestData
        self.benchPutMD5 = benchPutMD5
        self.benchCheckLength = benchCheckLength
        self.makeQuotaGB = makeQuotaGB
        self.blockBlobTier = blockBlobTier
        self.pageBlobTier = pageBlobTier
        self.rehydratePriority = rehydratePriority
        self.metadata = metadata
        self.blobTags = blobTags
        self.includePath = includePath
        self.excludePath = excludePath
        self.listOfFiles = listOfFiles
        self.showSensitiveEnvironment = showSensitiveEnvironment
    }
}

public struct AzCopyInvocation: Equatable, Sendable {
    public var executableURL: URL
    public var arguments: [String]
    public var environment: [String: String]

    public init(executableURL: URL, arguments: [String], environment: [String: String] = [:]) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
    }

    public var redactedPreview: String {
        ([executableURL.path] + arguments)
            .map(CredentialRedactor.redact)
            .joined(separator: " ")
    }
}

public struct AzCopyCommandBuilder: Sendable {
    public enum BuilderError: Error, Equatable, LocalizedError {
        case missingSource
        case missingDestination
        case unsupportedAccountKeyDirectAuth

        public var errorDescription: String? {
            switch self {
            case .missingSource:
                "A source path or URL is required."
            case .missingDestination:
                "A destination path or URL is required."
            case .unsupportedAccountKeyDirectAuth:
                "AzCopy v10 does not support direct account-key authentication. Use a SAS URL instead."
            }
        }
    }

    public init() {}

    public func build(request: TransferRequest, azCopyURL: URL) throws -> AzCopyInvocation {
        if case .accountKeyDerivedSAS = request.authentication {
            throw BuilderError.unsupportedAccountKeyDirectAuth
        }

        var arguments: [String]
        switch request.action {
        case .copy:
            try requireSourceAndDestination(request)
            arguments = ["copy", request.source, request.destination ?? ""]
        case .sync:
            try requireSourceAndDestination(request)
            arguments = ["sync", request.source, request.destination ?? ""]
        case .list:
            guard !request.source.isEmpty else { throw BuilderError.missingSource }
            arguments = ["list", request.source]
        case .remove:
            guard !request.source.isEmpty else { throw BuilderError.missingSource }
            arguments = ["remove", request.source]
        case .bench:
            guard !request.source.isEmpty else { throw BuilderError.missingSource }
            arguments = ["bench", request.source]
            appendFlag("--mode", value: request.benchMode, to: &arguments)
            appendFlag("--file-count", value: request.benchFileCount, to: &arguments)
            appendFlag("--size-per-file", value: request.benchSizePerFile, to: &arguments)
            appendFlag("--number-of-folders", value: request.benchNumberOfFolders, to: &arguments)
            if !request.benchDeleteTestData {
                arguments.append("--delete-test-data=false")
            }
            if request.benchPutMD5 {
                arguments.append("--put-md5")
            }
            if !request.benchCheckLength {
                arguments.append("--check-length=false")
            }
        case .make:
            guard !request.source.isEmpty else { throw BuilderError.missingSource }
            arguments = ["make", request.source]
            appendFlag("--quota-gb", value: request.makeQuotaGB, to: &arguments)
        case .setProperties:
            guard !request.source.isEmpty else { throw BuilderError.missingSource }
            arguments = ["set-properties", request.source]
            appendFlag("--block-blob-tier", value: request.blockBlobTier, defaultValue: "None", to: &arguments)
            appendFlag("--page-blob-tier", value: request.pageBlobTier, defaultValue: "None", to: &arguments)
            appendFlag("--rehydrate-priority", value: request.rehydratePriority, defaultValue: "Standard", to: &arguments)
            appendFlag("--metadata", value: request.metadata, to: &arguments)
            appendFlag("--blob-tags", value: request.blobTags, to: &arguments)
            appendFlag("--include-path", value: request.includePath, to: &arguments)
            appendFlag("--exclude-path", value: request.excludePath, to: &arguments)
            appendFlag("--list-of-files", value: request.listOfFiles, to: &arguments)
        case .env:
            arguments = ["env"]
            if request.showSensitiveEnvironment {
                arguments.append("--show-sensitive")
            }
        case .jobsList:
            arguments = ["jobs", "list"]
        case .jobsShow:
            guard !request.jobID.isEmpty else { throw BuilderError.missingSource }
            arguments = ["jobs", "show", request.jobID]
            appendFlag("--with-status", value: request.jobTransferStatus, to: &arguments)
        case .jobsResume:
            guard !request.jobID.isEmpty else { throw BuilderError.missingSource }
            arguments = ["jobs", "resume", request.jobID]
            appendFlag("--source-sas", value: request.sourceSAS, to: &arguments)
            appendFlag("--destination-sas", value: request.destinationSAS, to: &arguments)
            appendFlag("--include", value: request.includePath, to: &arguments)
            appendFlag("--exclude", value: request.excludePath, to: &arguments)
        case .jobsRemove:
            guard !request.jobID.isEmpty else { throw BuilderError.missingSource }
            arguments = ["jobs", "remove", request.jobID]
        case .jobsClean:
            arguments = ["jobs", "clean"]
        case .loginStatus:
            arguments = ["login", "status"]
        case .logout:
            arguments = ["logout"]
        }

        if request.recursive, supportsRecursive(request.action) {
            arguments.append("--recursive=true")
        }
        if request.dryRun, supportsDryRun(request.action) {
            arguments.append("--dry-run")
        }
        if let overwrite = request.overwrite {
            arguments.append("--overwrite=\(overwrite)")
        }
        if let deleteDestination = request.deleteDestination {
            arguments.append("--delete-destination=\(deleteDestination)")
        }
        arguments.append(contentsOf: request.extraFlags)

        return AzCopyInvocation(
            executableURL: azCopyURL,
            arguments: arguments,
            environment: request.authentication.environment
        )
    }

    public func buildLogin(method: AuthenticationMethod, azCopyURL: URL) throws -> AzCopyInvocation {
        guard let arguments = method.loginArguments else {
            return AzCopyInvocation(executableURL: azCopyURL, arguments: [], environment: method.environment)
        }
        return AzCopyInvocation(executableURL: azCopyURL, arguments: arguments, environment: method.environment)
    }

    private func requireSourceAndDestination(_ request: TransferRequest) throws {
        guard !request.source.isEmpty else { throw BuilderError.missingSource }
        guard let destination = request.destination, !destination.isEmpty else {
            throw BuilderError.missingDestination
        }
    }

    private func appendFlag(_ name: String, value: String, defaultValue: String = "", to arguments: inout [String]) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, trimmedValue != defaultValue else { return }
        arguments.append("\(name)=\(trimmedValue)")
    }

    private func supportsRecursive(_ action: TransferAction) -> Bool {
        switch action {
        case .copy, .sync, .remove, .setProperties:
            true
        default:
            false
        }
    }

    private func supportsDryRun(_ action: TransferAction) -> Bool {
        switch action {
        case .copy, .sync, .remove, .setProperties:
            true
        default:
            false
        }
    }
}
