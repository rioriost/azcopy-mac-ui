import Foundation

public struct SecurityPolicy: Sendable {
    public enum Violation: Error, Equatable, LocalizedError {
        case missingExecutable
        case executableIsNotAbsolute
        case shellExecutableDisallowed
        case insecureAzureURL(String)
        case accountKeyDirectAuthUnsupported

        public var errorDescription: String? {
            switch self {
            case .missingExecutable:
                "The AzCopy executable path is missing."
            case .executableIsNotAbsolute:
                "The AzCopy executable must be referenced by an absolute path."
            case .shellExecutableDisallowed:
                "Shell execution is not allowed."
            case .insecureAzureURL(let value):
                "Azure URL must use HTTPS: \(value)"
            case .accountKeyDirectAuthUnsupported:
                "Direct account-key authentication is not supported by AzCopy v10."
            }
        }
    }

    public var allowInsecureLocalhost: Bool

    public init(allowInsecureLocalhost: Bool = false) {
        self.allowInsecureLocalhost = allowInsecureLocalhost
    }

    public func validate(invocation: AzCopyInvocation) throws {
        let executablePath = invocation.executableURL.path
        guard !executablePath.isEmpty else { throw Violation.missingExecutable }
        guard executablePath.hasPrefix("/") else { throw Violation.executableIsNotAbsolute }

        let executableName = invocation.executableURL.lastPathComponent
        if ["sh", "bash", "zsh", "fish", "env"].contains(executableName) {
            throw Violation.shellExecutableDisallowed
        }

        for argument in invocation.arguments {
            try validateURLString(argument)
        }

        if invocation.environment.keys.contains("AZCOPY_ACCOUNT_KEY") {
            throw Violation.accountKeyDirectAuthUnsupported
        }
    }

    private func validateURLString(_ value: String) throws {
        guard let url = URL(string: value),
              let host = url.host,
              host.contains(".blob.core.") || host.contains(".file.core.") else {
            return
        }

        if url.scheme == "https" {
            return
        }

        if allowInsecureLocalhost, ["localhost", "127.0.0.1", "::1"].contains(host) {
            return
        }

        throw Violation.insecureAzureURL(value)
    }
}

