import Foundation
import Darwin

public struct AzCopyOutputEvent: Equatable, Sendable {
    public enum Stream: Equatable, Sendable {
        case standardOutput
        case standardError
    }

    public var stream: Stream
    public var text: String

    public init(stream: Stream, text: String) {
        self.stream = stream
        self.text = text
    }
}

public protocol AzCopyRunning: Sendable {
    /// The callback is awaited for backpressure and must return promptly.
    func run(
        _ invocation: AzCopyInvocation,
        onOutput: @escaping @Sendable (AzCopyOutputEvent) async -> Void
    ) async throws -> AzCopyRunResult
}

public extension AzCopyRunning {
    func run(_ invocation: AzCopyInvocation) async throws -> AzCopyRunResult {
        try await run(invocation, onOutput: { _ in })
    }
}

public struct AzCopyRunResult: Equatable, Sendable {
    public var exitCode: Int32
    public var output: String
    public var errorOutput: String
    public var outputTruncated: Bool
    public var errorOutputTruncated: Bool

    public init(
        exitCode: Int32,
        output: String,
        errorOutput: String,
        outputTruncated: Bool = false,
        errorOutputTruncated: Bool = false
    ) {
        self.exitCode = exitCode
        self.output = output
        self.errorOutput = errorOutput
        self.outputTruncated = outputTruncated
        self.errorOutputTruncated = errorOutputTruncated
    }
}

public final class AzCopyProcessRunner: AzCopyRunning {
    public enum RunnerError: Error, Equatable, LocalizedError {
        case validationFailed(String)
        case launchFailed(String)
        case outputReadFailed(String)

        public var errorDescription: String? {
            switch self {
            case .validationFailed(let message):
                message
            case .launchFailed(let message):
                "Failed to launch AzCopy: \(message)"
            case .outputReadFailed(let message):
                "Failed to read process output: \(message)"
            }
        }
    }

    private let securityPolicy: SecurityPolicy
    private let maximumCapturedBytesPerStream: Int

    /// Captures the tail of each stream, including a truncation marker, in at least 128 bytes.
    public init(
        securityPolicy: SecurityPolicy = SecurityPolicy(),
        maximumCapturedBytesPerStream: Int = 1_048_576
    ) {
        self.securityPolicy = securityPolicy
        self.maximumCapturedBytesPerStream = max(128, maximumCapturedBytesPerStream)
    }

    public func run(
        _ invocation: AzCopyInvocation,
        onOutput: @escaping @Sendable (AzCopyOutputEvent) async -> Void
    ) async throws -> AzCopyRunResult {
        try Task.checkCancellation()
        let environment = Self.childEnvironment(
            inherited: ProcessInfo.processInfo.environment,
            overriding: invocation.environment
        )
        let secrets = Self.secrets(in: invocation, environment: environment)
        do {
            try securityPolicy.validate(invocation: invocation)
        } catch {
            try Task.checkCancellation()
            throw RunnerError.validationFailed(Self.sanitize(error.localizedDescription, secrets: secrets))
        }

        let standardOutput = Pipe()
        let standardError = Pipe()
        let lifecycle = ProcessLifecycle(
            invocation: invocation,
            environment: environment,
            standardOutput: standardOutput,
            standardError: standardError
        )
        defer {
            lifecycle.finish()
            for pipe in [standardOutput, standardError] {
                try? pipe.fileHandleForReading.close()
                try? pipe.fileHandleForWriting.close()
            }
        }

        return try await withTaskCancellationHandler {
            do {
                try Self.makeNonblocking(standardOutput.fileHandleForReading)
                try Self.makeNonblocking(standardError.fileHandleForReading)
                try lifecycle.launch()
                try standardOutput.fileHandleForWriting.close()
                try standardError.fileHandleForWriting.close()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A failure closing a parent write handle must also stop a successfully launched child.
                lifecycle.stop()
                await lifecycle.waitForExit()
                try Task.checkCancellation()
                throw RunnerError.launchFailed(Self.sanitize(error.localizedDescription, secrets: secrets))
            }

            var output = OutputReader(handle: standardOutput.fileHandleForReading, secrets: secrets,
                                      limit: maximumCapturedBytesPerStream)
            var errorOutput = OutputReader(handle: standardError.fileHandleForReading, secrets: secrets,
                                           limit: maximumCapturedBytesPerStream)
            var readFailure: String?
            var exitedAt: ContinuousClock.Instant?
            while true {
                var receivedData = false
                for stream in [AzCopyOutputEvent.Stream.standardOutput, .standardError] {
                    do {
                        let text: String
                        let readBytes: Bool
                        if stream == .standardOutput {
                            (text, readBytes) = try output.read()
                        } else {
                            (text, readBytes) = try errorOutput.read()
                        }
                        receivedData = receivedData || readBytes
                        if !text.isEmpty {
                            await onOutput(AzCopyOutputEvent(stream: stream, text: text))
                        }
                    } catch {
                        readFailure = readFailure ?? error.localizedDescription
                        lifecycle.stop()
                    }
                }

                if !lifecycle.isRunning {
                    if output.finished && errorOutput.finished { break }
                    let now = ContinuousClock.now
                    exitedAt = exitedAt ?? now
                    // Descendants must not keep this invocation alive by retaining inherited pipes.
                    if let exitedAt, now - exitedAt >= .seconds(1) {
                        readFailure = readFailure ?? "Output pipes remained open after the child exited."
                        break
                    }
                }
                if !receivedData { await Self.pollDelay() }
            }
            for (stream, text) in [
                (AzCopyOutputEvent.Stream.standardOutput, output.finish()),
                (.standardError, errorOutput.finish())
            ] where !text.isEmpty {
                await onOutput(AzCopyOutputEvent(stream: stream, text: text))
            }
            try Task.checkCancellation()
            if let readFailure {
                throw RunnerError.outputReadFailed(Self.sanitize(readFailure, secrets: secrets))
            }
            return AzCopyRunResult(
                exitCode: lifecycle.exitCode,
                output: output.capture.text,
                errorOutput: errorOutput.capture.text,
                outputTruncated: output.capture.truncated || output.sanitizer.omittedOutput,
                errorOutputTruncated: errorOutput.capture.truncated || errorOutput.sanitizer.omittedOutput
            )
        } onCancel: {
            lifecycle.cancel()
        }
    }

    static func childEnvironment(inherited: [String: String], overriding: [String: String]) -> [String: String] {
        let operationalKeys: Set<String> = [
            "PATH", "HOME", "USER", "LOGNAME", "LANG", "TMPDIR", "TERM", "TZ",
            "AZURE_CONFIG_DIR", "SSL_CERT_FILE", "SSL_CERT_DIR", "REQUESTS_CA_BUNDLE",
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY"
        ]
        let inherited = inherited.filter { key, _ in
            let key = key.uppercased()
            if key.hasPrefix("AZCOPY_") {
                return !key.hasPrefix("AZCOPY_SPA_") && !key.hasPrefix("AZCOPY_MSI_")
                    && key != "AZCOPY_AUTO_LOGIN_TYPE" && key != "AZCOPY_TENANT_ID"
                    && !isSecretName(key) && !key.contains("OAUTH")
            }
            return operationalKeys.contains(key) || key.hasPrefix("LC_")
        }
        return inherited.merging(overriding) { _, selected in selected }
    }

    private static func isSecretName(_ name: String) -> Bool {
        let name = name.uppercased()
        return ["SECRET", "PASSWORD", "TOKEN", "ACCOUNT_KEY", "SAS", "SIGNATURE"].contains {
            name.contains($0)
        }
    }

    private static func secrets(in invocation: AzCopyInvocation, environment: [String: String]) -> [String] {
        var secrets = environment.compactMap { key, value in isSecretName(key) ? value : nil }
        for (key, value) in environment where key.uppercased().hasSuffix("_PROXY") {
            if let url = URLComponents(string: value), let password = url.password {
                secrets.append(password)
                secrets.append(value)
            }
        }
        var secretValueFollows = false
        for argument in invocation.arguments {
            if secretValueFollows { secrets.append(argument) }
            let pieces = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            secretValueFollows = pieces.count == 1 && argument.hasPrefix("--") && isSecretName(argument)
            if argument.hasPrefix("--"), isSecretName(String(pieces[0])), pieces.count == 2 {
                secrets.append(String(pieces[1]))
            }
            if let components = URLComponents(string: argument) {
                if let password = components.password { secrets.append(password) }
                if let user = components.user { secrets.append(user) }
                for item in components.queryItems ?? [] {
                    if ["sig", "signature", "sk", "skey", "token", "access_token", "refresh_token"].contains(item.name.lowercased()),
                       let value = item.value {
                        secrets.append(value)
                        if let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                            secrets.append(encoded)
                        }
                    }
                }
            }
        }
        return Array(Set(secrets.filter { !$0.isEmpty })).sorted { $0.count > $1.count }
    }

    private static func sanitize(_ text: String, secrets: [String]) -> String {
        secrets.reduce(CredentialRedactor.redact(text)) {
            $0.replacingOccurrences(of: $1, with: "<redacted>")
        }
    }

    private static func makeNonblocking(_ handle: FileHandle) throws {
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    fileprivate static func pollDelay() async {
        // Unlike Task.sleep, this still yields while a cancelled task drains its child's pipes.
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(10)) {
                continuation.resume()
            }
        }
    }
}

/// Only this locked lifecycle is unchecked Sendable. All Process access, launch/cancel races,
/// completion, and escalation timers are serialized by the lock; pipe readers remain task-local.
private final class ProcessLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var launched = false
    private var cancelled = false
    private var finished = false
    private var stopping = false
    private var timers: [DispatchWorkItem] = []

    init(invocation: AzCopyInvocation, environment: [String: String], standardOutput: Pipe, standardError: Pipe) {
        process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = standardOutput
        process.standardError = standardError
    }

    func launch() throws {
        try lock.withLock {
            guard !cancelled else { throw CancellationError() }
            try process.run()
            launched = true
        }
    }

    var isRunning: Bool {
        lock.withLock { launched && process.isRunning }
    }

    var exitCode: Int32 {
        lock.withLock { process.terminationStatus }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            stopLocked()
        }
    }

    func stop() {
        lock.withLock { stopLocked() }
    }

    private func stopLocked() {
        guard launched, !finished, !stopping, process.isRunning else { return }
        stopping = true
        _ = Darwin.kill(process.processIdentifier, SIGINT)
        for (delay, signal) in [(0.4, SIGTERM), (1.0, SIGKILL)] {
            let timer = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.lock.withLock {
                    guard !self.finished, self.launched, self.process.isRunning else { return }
                    // Never target a process name or process group, and never signal after completion.
                    _ = Darwin.kill(self.process.processIdentifier, signal)
                }
            }
            timers.append(timer)
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: timer)
        }
    }

    func waitForExit() async {
        while isRunning { await AzCopyProcessRunner.pollDelay() }
    }

    func finish() {
        lock.withLock {
            finished = true
            timers.forEach { $0.cancel() }
            timers.removeAll()
        }
    }
}

private struct OutputReader {
    let handle: FileHandle
    var sanitizer: OutputSanitizer
    var capture: BoundedOutput
    var finished = false

    init(handle: FileHandle, secrets: [String], limit: Int) {
        self.handle = handle
        sanitizer = OutputSanitizer(secrets: secrets)
        capture = BoundedOutput(limit: limit)
    }

    mutating func read() throws -> (String, Bool) {
        guard !finished else { return ("", false) }
        var bytes = [UInt8](repeating: 0, count: 16_384)
        let count = bytes.withUnsafeMutableBytes {
            Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count)
        }
        if count < 0 {
            if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { return ("", false) }
            finished = true
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        if count == 0 {
            finished = true
            return (finish(), false)
        }
        let text = sanitizer.append(Array(bytes.prefix(count)))
        capture.append(text)
        return (text, true)
    }

    mutating func finish() -> String {
        let text = sanitizer.finish()
        capture.append(text)
        finished = true
        return text
    }
}

private struct BoundedOutput {
    static let marker = "[Earlier output truncated]\n"
    let limit: Int
    private var bytes: [UInt8] = []
    private(set) var truncated = false

    init(limit: Int) { self.limit = limit }

    mutating func append(_ text: String) {
        bytes.append(contentsOf: text.utf8)
        if bytes.count > limit || (truncated && bytes.count > limit - Self.marker.utf8.count) {
            truncated = true
            bytes = Array(bytes.suffix(limit - Self.marker.utf8.count))
            while let first = bytes.first, first & 0xC0 == 0x80 { bytes.removeFirst() }
        }
    }

    var text: String {
        (truncated ? Self.marker : "") + String(decoding: bytes, as: UTF8.self)
    }
}

/// Known credentials are matched before tokenization, even across whitespace/read boundaries.
/// Credential-shaped tokens are withheld until complete; ordinary no-newline prompts stream live.
/// Unterminated tokens are bounded and omitted rather than risking disclosure of a partial secret.
private struct OutputSanitizer {
    private static let markers = [
        "sig", "signature", "sk", "skey", "token", "access_token", "refresh_token",
        "--source-sas", "--destination-sas", "AZCOPY_SPA_CLIENT_SECRET",
        "AZCOPY_SPA_CERT_PASSWORD", "AZCOPY_ACCOUNT_KEY", "authorization", "bearer",
        "client_secret", "clientSecret", "password", "account_key", "accountKey",
        "source-sas", "destination-sas", "%", "\\"
    ].map { Array($0.lowercased().utf8) }
    private static let tokenLimit = 65_536
    private var literalRedactor: LiteralRedactor
    private var token: [UInt8] = []
    private var emitted = 0
    private var quote: UInt8?
    private var escaped = false
    private var discarding = false
    private var secretFollows = false
    private(set) var omittedOutput = false

    init(secrets: [String]) { literalRedactor = LiteralRedactor(secrets: secrets) }

    mutating func append(_ bytes: [UInt8]) -> String {
        consume(literalRedactor.append(bytes), final: false)
    }

    mutating func finish() -> String {
        consume(literalRedactor.finish(), final: true)
    }

    private mutating func consume(_ bytes: [UInt8], final: Bool) -> String {
        var result = ""
        for byte in bytes {
            let whitespace = byte == 32 || (9...13).contains(byte)
            if whitespace && quote == nil {
                result += completeToken()
                result += String(UnicodeScalar(byte))
                continue
            }
            if let delimiter = quote {
                if byte == delimiter && !escaped { quote = nil }
                escaped = byte == 92 && !escaped
            } else if (byte == 34 || byte == 39)
                        && (token.isEmpty || token.last.map { [61, 58, 123, 91, 44].contains($0) } == true) {
                quote = byte
            }
            guard !discarding else { continue }
            token.append(byte)
            if token.count > Self.tokenLimit {
                omittedOutput = true
                result += "[Oversized output token omitted]"
                token.removeAll(keepingCapacity: true)
                emitted = 0
                discarding = true
            }
        }
        if final {
            result += completeToken()
        } else if !discarding && !secretFollows {
            let end = safePrefixEnd()
            if end > emitted {
                result += String(decoding: token[emitted..<end], as: UTF8.self)
                emitted = end
            }
        }
        return result
    }

    private mutating func completeToken() -> String {
        defer {
            token.removeAll(keepingCapacity: true)
            emitted = 0
            quote = nil
            escaped = false
            discarding = false
        }
        if discarding {
            secretFollows = false
            return ""
        }
        guard !token.isEmpty else { return "" }
        let text = String(decoding: token, as: UTF8.self)
        let redacted: String
        if secretFollows {
            if text == "=" || text == ":" || ["bearer", "basic"].contains(text.lowercased()) { return text }
            redacted = "<redacted>"
            secretFollows = Self.isSecretName(text)
        } else {
            if quote != nil, Self.markers.dropLast(2).contains(where: {
                Data(token.map { (65...90).contains($0) ? $0 + 32 : $0 }).range(of: Data($0)) != nil
            }) {
                // EOF/cancellation can cut a quoted credential before its closing quote.
                redacted = String(decoding: token.prefix(emitted), as: UTF8.self) + "<redacted>"
            } else {
                redacted = CredentialRedactor.redact(text)
            }
            secretFollows = Self.isSecretName(text)
        }
        let prefix = String(decoding: token.prefix(emitted), as: UTF8.self)
        guard redacted.hasPrefix(prefix) else { return "<redacted>" }
        return String(redacted.dropFirst(prefix.count))
    }

    private static func isSecretName(_ text: String) -> Bool {
        let name = text.trimmingCharacters(in: CharacterSet(charactersIn: "{}[],\"':=")).lowercased()
        return markers.dropLast(2).contains {
            let marker = String(decoding: $0, as: UTF8.self)
            return name == marker || name.hasSuffix("\"\(marker)") || name.hasSuffix("'\(marker)")
        }
    }

    private func safePrefixEnd() -> Int {
        guard quote == nil else { return emitted }
        let lower = token.map { (65...90).contains($0) ? $0 + 32 : $0 }
        var end = completeUTF8End()
        for marker in Self.markers {
            if let range = Data(lower).range(of: Data(marker)) {
                end = min(end, range.lowerBound)
            }
            let length = min(lower.count, marker.count - 1)
            if length > 0 {
                for count in (1...length).reversed() where lower.suffix(count).elementsEqual(marker.prefix(count)) {
                    end = min(end, lower.count - count)
                    break
                }
            }
        }
        return end
    }

    private func completeUTF8End() -> Int {
        guard !token.isEmpty else { return 0 }
        var start = token.count - 1
        while start > 0 && token[start] & 0xC0 == 0x80 { start -= 1 }
        let first = token[start]
        let expected = first & 0xF8 == 0xF0 ? 4 : first & 0xF0 == 0xE0 ? 3 : first & 0xE0 == 0xC0 ? 2 : 1
        return token.count - start < expected ? start : token.count
    }
}

private struct LiteralRedactor {
    private let secrets: [[UInt8]]
    private let firstBytes: Set<UInt8>
    private var pending: [UInt8] = []

    init(secrets: [String]) {
        self.secrets = secrets.map { Array($0.utf8) }.filter { !$0.isEmpty }
        firstBytes = Set(self.secrets.compactMap(\.first))
    }

    mutating func append(_ bytes: [UInt8]) -> [UInt8] {
        guard !secrets.isEmpty else { return bytes }
        var result: [UInt8] = []
        for byte in bytes {
            if pending.isEmpty && !firstBytes.contains(byte) {
                result.append(byte)
                continue
            }
            pending.append(byte)
            flush(into: &result, final: false)
        }
        return result
    }

    mutating func finish() -> [UInt8] {
        var result: [UInt8] = []
        flush(into: &result, final: true)
        return result
    }

    private mutating func flush(into result: inout [UInt8], final: Bool) {
        while !pending.isEmpty {
            let candidates = secrets.filter { $0.starts(with: pending) }
            if !final, candidates.contains(where: { $0.count > pending.count }) { return }
            if final, !candidates.isEmpty {
                result.append(contentsOf: "<redacted>".utf8)
                pending.removeAll()
                return
            }
            if let match = secrets.first(where: { pending.starts(with: $0) }) {
                result.append(contentsOf: "<redacted>".utf8)
                pending.removeFirst(match.count)
            } else if !final, !candidates.isEmpty {
                return
            } else {
                result.append(pending.removeFirst())
            }
        }
    }
}
