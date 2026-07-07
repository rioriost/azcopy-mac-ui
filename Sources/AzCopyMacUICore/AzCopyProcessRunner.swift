import Foundation

public struct AzCopyRunResult: Equatable, Sendable {
    public var exitCode: Int32
    public var output: String
    public var errorOutput: String

    public init(exitCode: Int32, output: String, errorOutput: String) {
        self.exitCode = exitCode
        self.output = output
        self.errorOutput = errorOutput
    }
}

public final class AzCopyProcessRunner: Sendable {
    public enum RunnerError: Error, Equatable, LocalizedError {
        case validationFailed(String)
        case launchFailed(String)

        public var errorDescription: String? {
            switch self {
            case .validationFailed(let message):
                message
            case .launchFailed(let message):
                "Failed to launch AzCopy: \(message)"
            }
        }
    }

    private let securityPolicy: SecurityPolicy

    public init(securityPolicy: SecurityPolicy = SecurityPolicy()) {
        self.securityPolicy = securityPolicy
    }

    public func run(_ invocation: AzCopyInvocation) async throws -> AzCopyRunResult {
        do {
            try securityPolicy.validate(invocation: invocation)
        } catch {
            throw RunnerError.validationFailed(error.localizedDescription)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = invocation.executableURL
            process.arguments = invocation.arguments
            process.environment = ProcessInfo.processInfo.environment.merging(invocation.environment) { _, new in new }

            let standardOutput = Pipe()
            let standardError = Pipe()
            process.standardOutput = standardOutput
            process.standardError = standardError

            process.terminationHandler = { process in
                let output = String(data: standardOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let errorOutput = String(data: standardError.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: AzCopyRunResult(
                    exitCode: process.terminationStatus,
                    output: CredentialRedactor.redact(output),
                    errorOutput: CredentialRedactor.redact(errorOutput)
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: RunnerError.launchFailed(error.localizedDescription))
            }
        }
    }
}

