import Foundation

public enum TransferAction: String, CaseIterable, Sendable {
    case copy
    case sync
    case list
    case remove
    case jobsList
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

    public init(
        action: TransferAction,
        source: String = "",
        destination: String? = nil,
        recursive: Bool = false,
        dryRun: Bool = false,
        overwrite: Bool? = nil,
        deleteDestination: Bool? = nil,
        extraFlags: [String] = [],
        authentication: AuthenticationMethod = .userIdentity(tenantID: nil)
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
        case .jobsList:
            arguments = ["jobs", "list"]
        case .loginStatus:
            arguments = ["login", "status"]
        case .logout:
            arguments = ["logout"]
        }

        if request.recursive {
            arguments.append("--recursive=true")
        }
        if request.dryRun {
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
}

