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

    public var supportsRecursive: Bool {
        switch self {
        case .copy, .sync, .remove, .setProperties: true
        default: false
        }
    }

    public var supportsDryRun: Bool { supportsRecursive }

    public var supportsCapMbps: Bool {
        switch self {
        case .copy, .sync, .bench: true
        default: false
        }
    }

    public var supportsPatternFlags: Bool { supportsRecursive }

    fileprivate var requiresAuthentication: Bool {
        switch self {
        case .copy, .sync, .list, .remove, .bench, .make, .setProperties, .jobsResume: true
        default: false
        }
    }
}

public enum ExtraFlagsParser {
    public enum ParseError: Error, Equatable, LocalizedError {
        case unterminatedQuote
        case trailingEscape
        case nullCharacter

        public var errorDescription: String? {
            switch self {
            case .unterminatedQuote: "Additional flags contain an unclosed quote."
            case .trailingEscape: "Additional flags end with a backslash without a character to escape."
            case .nullCharacter: "Additional flags cannot contain a null character."
            }
        }
    }

    /// Splits on whitespace outside quotes. Single quotes preserve literal text;
    /// double quotes preserve whitespace. Outside single quotes, backslash escapes
    /// the next character. Adjacent quoted/unquoted segments form one argument,
    /// including empty quoted arguments. No shell expansion or evaluation occurs.
    public static func parse(_ text: String) throws -> [String] {
        var arguments: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        var started = false

        for character in text {
            guard character != "\0" else { throw ParseError.nullCharacter }
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\", quote != "'" {
                escaped = true
                started = true
            } else if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
            } else if character == "'" || character == "\"" {
                quote = character
                started = true
            } else if character.isWhitespace {
                if started {
                    arguments.append(current)
                    current = ""
                    started = false
                }
            } else {
                current.append(character)
                started = true
            }
        }

        guard !escaped else { throw ParseError.trailingEscape }
        guard quote == nil else { throw ParseError.unterminatedQuote }
        if started { arguments.append(current) }
        return arguments
    }
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
    public var capMbps: String
    public var includePattern: String
    public var excludePattern: String

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
        showSensitiveEnvironment: Bool = false,
        capMbps: String = "",
        includePattern: String = "",
        excludePattern: String = ""
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
        self.capMbps = capMbps
        self.includePattern = includePattern
        self.excludePattern = excludePattern
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
        CredentialRedactor.redact(arguments: [executableURL.path] + arguments)
            .map(CredentialRedactor.quoteArgument)
            .joined(separator: " ")
    }
}

public struct AzCopyCommandBuilder: Sendable {
    public enum BuilderError: Error, Equatable, LocalizedError {
        case missingSource
        case missingDestination
        case unsupportedAccountKeyDirectAuth
        case reservedExtraFlag(String)
        case argumentTerminatorDisallowed
        case invalidArgument
        case unsupportedLoginMethod(String)

        public var errorDescription: String? {
            switch self {
            case .missingSource:
                "A source path or URL is required."
            case .missingDestination:
                "A destination path or URL is required."
            case .unsupportedAccountKeyDirectAuth:
                "AzCopy v10 does not support direct account-key authentication. Use a SAS URL instead."
            case .reservedExtraFlag(let flag):
                "\(flag) is managed by the operation form. Remove it from Additional flags and use the corresponding control."
            case .argumentTerminatorDisallowed:
                "Additional flags cannot contain -- because it disables parsing of the operation's safety flags."
            case .invalidArgument:
                "Paths, job IDs, and additional flags cannot contain null characters; paths and job IDs must not start with a hyphen. Use an absolute path or prefix a local path with ./."
            case .unsupportedLoginMethod(let guidance):
                guidance
            }
        }
    }

    public init() {}

    public func build(request: TransferRequest, azCopyURL: URL) throws -> AzCopyInvocation {
        if request.action.requiresAuthentication {
            if case .accountKeyDerivedSAS = request.authentication {
                throw BuilderError.unsupportedAccountKeyDirectAuth
            }
            try request.authentication.validate()
        }
        try validateExtraFlags(request.extraFlags, action: request.action)

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

        if request.action.supportsRecursive {
            arguments.append("--recursive=\(request.recursive)")
        }
        if request.dryRun, request.action.supportsDryRun {
            arguments.append("--dry-run")
        }
        if request.action == .copy, let overwrite = request.overwrite {
            arguments.append("--overwrite=\(overwrite)")
        }
        if request.action == .sync, let deleteDestination = request.deleteDestination {
            arguments.append("--delete-destination=\(deleteDestination)")
        }
        if request.action.supportsCapMbps {
            appendFlag("--cap-mbps", value: request.capMbps, to: &arguments)
        }
        if request.action.supportsPatternFlags {
            appendFlag("--include-pattern", value: request.includePattern, to: &arguments)
            appendFlag("--exclude-pattern", value: request.excludePattern, to: &arguments)
        }
        let positionalValues: [String]
        switch request.action {
        case .copy, .sync: positionalValues = [request.source, request.destination ?? ""]
        case .list, .remove, .bench, .make, .setProperties: positionalValues = [request.source]
        case .jobsShow, .jobsResume, .jobsRemove: positionalValues = [request.jobID]
        default: positionalValues = []
        }
        guard !positionalValues.contains(where: { $0.hasPrefix("-") }),
              !arguments.contains(where: { $0.contains("\0") }) else {
            throw BuilderError.invalidArgument
        }
        arguments.append(contentsOf: request.extraFlags)

        return AzCopyInvocation(
            executableURL: azCopyURL,
            arguments: arguments,
            environment: request.action.requiresAuthentication ? request.authentication.environment : [:]
        )
    }

    public func buildLogin(method: AuthenticationMethod, azCopyURL: URL) throws -> AzCopyInvocation {
        try method.validate()
        guard let arguments = method.loginArguments else {
            throw BuilderError.unsupportedLoginMethod(method.signInGuidance)
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

    private func validateExtraFlags(_ arguments: [String], action: TransferAction) throws {
        var reservedFlags: Set<String> = ["--dry-run", "--recursive", "--overwrite", "--delete-destination"]
        switch action {
        case .bench:
            reservedFlags.formUnion(["--mode", "--file-count", "--size-per-file", "--number-of-folders", "--delete-test-data", "--put-md5", "--check-length"])
        case .make:
            reservedFlags.insert("--quota-gb")
        case .setProperties:
            reservedFlags.formUnion(["--block-blob-tier", "--page-blob-tier", "--rehydrate-priority", "--metadata", "--blob-tags", "--include-path", "--exclude-path", "--list-of-files"])
        case .env:
            reservedFlags.insert("--show-sensitive")
        case .jobsShow:
            reservedFlags.insert("--with-status")
        case .jobsResume:
            reservedFlags.formUnion(["--source-sas", "--destination-sas", "--include", "--exclude"])
        default:
            break
        }
        if action.supportsCapMbps {
            reservedFlags.insert("--cap-mbps")
        }
        if action.supportsPatternFlags {
            reservedFlags.formUnion(["--include-pattern", "--exclude-pattern"])
        }
        for argument in arguments {
            guard !argument.contains("\0") else { throw BuilderError.invalidArgument }
            guard argument != "--" else { throw BuilderError.argumentTerminatorDisallowed }
            let name = String(argument.prefix { $0 != "=" }).lowercased()
            if reservedFlags.contains(name) {
                throw BuilderError.reservedExtraFlag(name)
            }
        }
    }
}
