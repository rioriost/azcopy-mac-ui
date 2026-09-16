import Foundation
import Darwin
import Testing
@testable import AzCopyMacUICore

@Suite("AzCopyProcessRunner")
struct AzCopyProcessRunnerTests {
    @Test("runs absolute executable without shell")
    func runsExecutable() async throws {
        let runner = AzCopyProcessRunner()
        let invocation = AzCopyInvocation(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello"]
        )

        let result = try await runner.run(invocation)

        #expect(result.exitCode == 0)
        #expect(result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
        #expect(!result.outputTruncated)
        #expect(!result.errorOutputTruncated)
    }

    @Test("surfaces validation errors")
    func surfacesValidationErrors() async {
        let runner = AzCopyProcessRunner()
        let invocation = AzCopyInvocation(
            executableURL: URL(fileURLWithPath: "/bin/bash"),
            arguments: []
        )

        await #expect(throws: AzCopyProcessRunner.RunnerError.validationFailed(SecurityPolicy.Violation.shellExecutableDisallowed.localizedDescription)) {
            _ = try await runner.run(invocation)
        }
    }

    @Test("runner error descriptions are present")
    func runnerErrorDescriptions() {
        #expect(AzCopyProcessRunner.RunnerError.validationFailed("bad").errorDescription?.isEmpty == false)
        #expect(AzCopyProcessRunner.RunnerError.launchFailed("bad").errorDescription?.isEmpty == false)
        #expect(AzCopyProcessRunner.RunnerError.outputReadFailed("bad").errorDescription?.isEmpty == false)
    }

    @Test("drains more than pipe capacity from both streams concurrently")
    func simultaneousLargeOutput() async throws {
        let runner = AzCopyProcessRunner(maximumCapturedBytesPerStream: 3 * 1_048_576)
        let result = try await runner.run(fixtureInvocation("duplex"))
        #expect(result.exitCode == 0)
        #expect(result.output.utf8.count == 2_097_152 + "stdout complete\n".utf8.count)
        #expect(result.errorOutput.utf8.count == 2_097_152 + "stderr complete\n".utf8.count)
        #expect(result.output.hasSuffix("stdout complete\n"))
        #expect(result.errorOutput.hasSuffix("stderr complete\n"))
        #expect(!result.outputTruncated)
        #expect(!result.errorOutputTruncated)
    }

    @Test("delivers complete no-newline device prompts before the child can exit")
    func liveOutput() async throws {
        let fixture = try Self.fixture.get()
        let release = fixture.directory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: release) }
        let events = OutputEvents()
        let result = try await AzCopyProcessRunner().run(
            fixtureInvocation("live", release.path)
        ) { event in
            await events.append(event)
            if await events.text(for: .standardOutput).contains("ABCD-1234") {
                _ = FileManager.default.createFile(atPath: release.path, contents: Data())
            }
        }
        #expect(result.exitCode == 0)
        #expect(result.output == "To sign in, visit https://microsoft.com/devicelogin and enter code ABCD-1234")
        #expect(result.errorOutput == "Waiting for authentication")
        #expect(await events.text(for: .standardOutput) == result.output)
        #expect(await events.text(for: .standardError) == result.errorOutput)
    }

    @Test("preserves split UTF8, CR progress, LF, and an unterminated tail")
    func incrementalUTF8() async throws {
        let events = OutputEvents()
        let result = try await AzCopyProcessRunner().run(fixtureInvocation("utf8")) {
            await events.append($0)
        }
        #expect(result.output == "開始🙂\r50%\r\nDone 終")
        #expect(!result.output.contains("\u{FFFD}"))
        #expect(await events.text(for: .standardOutput) == result.output)
    }

    @Test("never emits split SAS, flag, quoted, or literal environment secrets")
    func streamingRedaction() async throws {
        let events = OutputEvents()
        var invocation = try fixtureInvocation("secrets")
        invocation.environment = ["AZCOPY_SPA_CLIENT_SECRET": "known multiword credential"]
        let result = try await AzCopyProcessRunner().run(invocation) {
            await events.append($0)
        }
        let observed = await events.text(for: .standardOutput) + events.text(for: .standardError)
        for secret in ["UNKNOWN_SIGNATURE", "FLAG_SIGNATURE", "QUOTED SECRET", "known multiword credential"] {
            #expect(!observed.contains(secret))
            #expect(!result.output.contains(secret))
            #expect(!result.errorOutput.contains(secret))
        }
        for fragment in ["UNKNOWN_", "SIGNATURE", "QUOTED", "multiword", "credential"] {
            #expect(!observed.contains(fragment))
        }
        #expect(result.output.contains("<redacted>"))
        #expect(result.errorOutput.contains("<redacted>"))
    }

    @Test("encoded keys and EOF inside credentials fail closed")
    func secretBoundariesAtEOF() async throws {
        let events = OutputEvents()
        var invocation = try fixtureInvocation("secret-boundaries")
        invocation.environment = ["AZCOPY_SPA_CLIENT_SECRET": "unfinished credential"]
        let result = try await AzCopyProcessRunner().run(invocation) {
            await events.append($0)
        }
        let observed = await events.text(for: .standardOutput) + events.text(for: .standardError)
        for fragment in ["ENCODED_SECRET", "QUOTED_UNFINISHED", "unfinished", "HEADER_SECRET"] {
            #expect(!observed.contains(fragment))
        }
        #expect(result.output.contains("<redacted>"))
        #expect(result.errorOutput.contains("<redacted>"))
    }

    @Test("URL user credentials never reach output callbacks")
    func urlCredentialsInOutput() async throws {
        let events = OutputEvents()
        let invocation = try fixtureInvocation(
            "echo", "https://stream-user:STREAM_PASSWORD@example.blob.core.windows.net/data"
        )
        let result = try await AzCopyProcessRunner().run(invocation) { await events.append($0) }
        let output = await events.text(for: .standardOutput)
        #expect(!output.contains("STREAM_PASSWORD"))
        #expect(!output.contains("stream-user"))
        #expect(output == result.output)
    }

    @Test("bounded result retention preserves final errors with an explicit marker")
    func boundedCapture() async throws {
        let result = try await AzCopyProcessRunner(maximumCapturedBytesPerStream: 1_024).run(
            fixtureInvocation("duplex")
        )
        #expect(result.output.utf8.count <= 1_024)
        #expect(result.errorOutput.utf8.count <= 1_024)
        #expect(result.output.hasPrefix("[Earlier output truncated]\n"))
        #expect(result.errorOutput.hasPrefix("[Earlier output truncated]\n"))
        #expect(result.outputTruncated)
        #expect(result.errorOutputTruncated)
        #expect(result.output.hasSuffix("stdout complete\n"))
        #expect(result.errorOutput.hasSuffix("stderr complete\n"))
    }

    @Test("bounds unterminated output without exposing a partial secret")
    func oversizedToken() async throws {
        let events = OutputEvents()
        let result = try await AzCopyProcessRunner(maximumCapturedBytesPerStream: 1_024).run(
            fixtureInvocation("oversized-secret")
        ) {
            await events.append($0)
        }
        let observed = await events.text(for: .standardOutput)
        #expect(!observed.contains("ZZZZ"))
        #expect(observed.contains("[Oversized output token omitted]"))
        #expect(result.output.utf8.count <= 1_024)
        #expect(result.output.hasSuffix("\ncomplete\n"))
        #expect(result.outputTruncated)
    }

    @Test("a pre-cancelled task never launches its executable")
    func cancellationBeforeLaunch() async throws {
        let fixture = try Self.fixture.get()
        let marker = fixture.directory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let gate = TestGate()
        let invocation = try fixtureInvocation("touch", marker.path)
        let task = Task {
            await gate.wait()
            return try await AzCopyProcessRunner().run(invocation)
        }
        task.cancel()
        await gate.open()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test("cancellation interrupts, drains final diagnostics, and never returns success")
    func gracefulCancellation() async throws {
        let ready = TestGate()
        let events = OutputEvents()
        let invocation = try fixtureInvocation("graceful")
        let task = Task {
            try await AzCopyProcessRunner().run(invocation) { event in
                await events.append(event)
                if await events.text(for: .standardOutput).contains("READY") { await ready.open() }
            }
        }
        await ready.wait()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await events.text(for: .standardError).contains("Stopped cleanly"))
        try await assertChildExited(events)
    }

    @Test("cancellation force-stops only its exact child when graceful signals are ignored")
    func forcedCancellation() async throws {
        let ready = TestGate()
        let events = OutputEvents()
        let invocation = try fixtureInvocation("resist")
        let task = Task {
            try await AzCopyProcessRunner().run(invocation) { event in
                await events.append(event)
                if await events.text(for: .standardOutput).contains("READY") { await ready.open() }
            }
        }
        await ready.wait()
        let start = ContinuousClock.now
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(ContinuousClock.now - start < .seconds(2.5))
        try await assertChildExited(events)
    }

    @Test("cancelling one invocation neither stops a peer nor poisons runner reuse")
    func independentCancellation() async throws {
        let runner = AzCopyProcessRunner()
        let firstReady = TestGate()
        let secondReady = TestGate()
        let firstEvents = OutputEvents()
        let secondEvents = OutputEvents()
        let invocation = try fixtureInvocation("resist")
        let first = Task {
            try await runner.run(invocation) { event in
                await firstEvents.append(event)
                if await firstEvents.text(for: .standardOutput).contains("READY") { await firstReady.open() }
            }
        }
        let second = Task {
            try await runner.run(invocation) { event in
                await secondEvents.append(event)
                if await secondEvents.text(for: .standardOutput).contains("READY") { await secondReady.open() }
            }
        }
        defer {
            first.cancel()
            second.cancel()
        }
        await firstReady.wait()
        await secondReady.wait()
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        let output = await secondEvents.text(for: .standardOutput)
        let pid = try #require(Int32(output.split(separator: " ").first.map(String.init) ?? ""))
        #expect(Darwin.kill(pid, 0) == 0)
        second.cancel()
        await #expect(throws: CancellationError.self) { try await second.value }
        try await assertChildExited(firstEvents)
        try await assertChildExited(secondEvents)
        #expect(try await runner.run(fixtureInvocation("echo", "reused")).output == "reused\n")
    }

    @Test("cancellation racing output delivery and exit cannot become success")
    func cancellationAtExit() async throws {
        let ready = TestGate()
        let release = TestGate()
        let invocation = try fixtureInvocation("echo", "done")
        let task = Task {
            try await AzCopyProcessRunner().run(invocation) { _ in
                await ready.open()
                await release.wait()
            }
        }
        await ready.wait()
        task.cancel()
        await release.open()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("stdin is closed for unsupported interactive prompts")
    func closedInput() async throws {
        let result = try await AzCopyProcessRunner().run(fixtureInvocation("stdin"))
        #expect(result.exitCode == 0)
        #expect(result.output == "stdin closed\n")
    }

    @Test("nonzero exits retain diagnostic output")
    func nonzeroExit() async throws {
        let result = try await AzCopyProcessRunner().run(fixtureInvocation("failure"))
        #expect(result.exitCode == 7)
        #expect(result.errorOutput == "fixture failure\n")
    }

    @Test("missing and non-executable paths fail without hanging")
    func launchFailures() async throws {
        let fixture = try Self.fixture.get()
        for url in [fixture.directory.appendingPathComponent("missing"), fixture.directory] {
            do {
                _ = try await AzCopyProcessRunner().run(AzCopyInvocation(executableURL: url, arguments: []))
                Issue.record("Expected launch failure for \(url.lastPathComponent)")
            } catch let error as AzCopyProcessRunner.RunnerError {
                guard case .launchFailed = error else {
                    Issue.record("Unexpected runner error: \(error)")
                    continue
                }
            }
        }
    }

    @Test("a runner supports repeated and concurrent invocations through its protocol")
    func repeatedCalls() async throws {
        let runner: any AzCopyRunning = AzCopyProcessRunner()
        for _ in 0..<3 {
            #expect(try await runner.run(fixtureInvocation("echo", "again")).output == "again\n")
        }
        try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<8 {
                let invocation = try fixtureInvocation("echo", "parallel-\(index)")
                group.addTask { try await runner.run(invocation).output }
            }
            var outputs: Set<String> = []
            for try await output in group { outputs.insert(output) }
            #expect(outputs.count == 8)
        }
    }

    @Test("selected authentication cannot inherit ambient credentials")
    func isolatedEnvironment() {
        let result = AzCopyProcessRunner.childEnvironment(
            inherited: [
                "PATH": "/usr/bin:/bin", "HOME": "/Users/fixture", "LANG": "ja_JP.UTF-8",
                "AZCOPY_AUTO_LOGIN_TYPE": "SPN", "AZCOPY_TENANT_ID": "ambient-tenant",
                "AZCOPY_SPA_CLIENT_SECRET": "ambient-secret", "AZCOPY_SPA_CERT_PATH": "ambient-cert",
                "AZCOPY_MSI_CLIENT_ID": "ambient-client", "AZCOPY_OAUTH_TOKEN_INFO": "ambient-token",
                "AZCOPY_ACCOUNT_KEY": "ambient-key", "AZCOPY_CONCURRENCY_VALUE": "16",
                "UNRELATED_API_SECRET": "not-for-this-child"
            ],
            overriding: ["AZCOPY_AUTO_LOGIN_TYPE": "DEVICE", "AZCOPY_TENANT_ID": "selected-tenant"]
        )
        #expect(result["AZCOPY_AUTO_LOGIN_TYPE"] == "DEVICE")
        #expect(result["AZCOPY_TENANT_ID"] == "selected-tenant")
        #expect(result["AZCOPY_CONCURRENCY_VALUE"] == "16")
        #expect(result["HOME"] == "/Users/fixture")
        #expect(!result.values.contains { $0.hasPrefix("ambient-") })
        #expect(result["UNRELATED_API_SECRET"] == nil)
    }

    private static let fixture: Result<RunnerFixture, Error> = Result { try RunnerFixture() }

    private func fixtureInvocation(_ mode: String, _ argument: String? = nil) throws -> AzCopyInvocation {
        let fixture = try Self.fixture.get()
        return AzCopyInvocation(
            executableURL: fixture.executable,
            arguments: [mode] + (argument.map { [$0] } ?? [])
        )
    }

    private func assertChildExited(_ events: OutputEvents) async throws {
        let output = await events.text(for: .standardOutput)
        let pid = try #require(Int32(output.split(separator: " ").first.map(String.init) ?? ""))
        let status = Darwin.kill(pid, 0)
        let error = errno
        #expect(status == -1)
        #expect(error == ESRCH)
    }
}

private actor OutputEvents {
    private var events: [AzCopyOutputEvent] = []

    func append(_ event: AzCopyOutputEvent) { events.append(event) }

    func text(for stream: AzCopyOutputEvent.Stream) -> String {
        events.filter { $0.stream == stream }.map(\.text).joined()
    }
}

private actor TestGate {
    private var opened = false

    func wait() async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !opened {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting for fixture coordination")
                return
            }
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(10)) {
                    continuation.resume()
                }
            }
        }
    }

    func open() { opened = true }
}

private final class RunnerFixture: Sendable {
    let directory: URL
    let executable: URL

    init() throws {
        directory = Self.buildDirectory
        executable = directory.appendingPathComponent("runner-fixture")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let source = directory.appendingPathComponent("fixture.c")
            try Self.source.write(to: source, atomically: false, encoding: .utf8)
            let compiler = Process()
            compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
            compiler.arguments = ["-std=c11", "-pthread", source.path, "-o", executable.path]
            compiler.environment = ProcessInfo.processInfo.environment.merging(["TMPDIR": directory.path]) { _, new in new }
            compiler.standardInput = FileHandle.nullDevice
            try compiler.run()
            compiler.waitUntilExit()
            guard compiler.terminationStatus == 0 else {
                throw AzCopyProcessRunner.RunnerError.launchFailed("Fixture compilation failed")
            }
            atexit {
                try? FileManager.default.removeItem(at: RunnerFixture.buildDirectory)
            }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    private static var buildDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/runner-fixtures/\(getpid())")
    }

    private static let source = #"""
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <unistd.h>
    #include <signal.h>
    #include <pthread.h>
    #include <fcntl.h>
    #include <errno.h>

    static volatile sig_atomic_t interrupted = 0;
    static void stop(int signal) { interrupted = 1; }
    static void put(int fd, const char *s) { write(fd, s, strlen(s)); }
    static void *flood(void *argument) {
        int fd = (int)(long)argument;
        char line[1024];
        memset(line, fd == 1 ? 'O' : 'E', sizeof(line));
        line[1023] = '\n';
        for (int i = 0; i < 2048; ++i) {
            size_t offset = 0;
            while (offset < sizeof(line)) {
                ssize_t count = write(fd, line + offset, sizeof(line) - offset);
                if (count < 0) { if (errno == EINTR) continue; return NULL; }
                offset += count;
            }
        }
        put(fd, fd == 1 ? "stdout complete\n" : "stderr complete\n");
        return NULL;
    }
    int main(int argc, char **argv) {
        alarm(15);
        if (argc < 2) return 2;
        if (!strcmp(argv[1], "duplex")) {
            pthread_t writer;
            pthread_create(&writer, NULL, flood, (void *)1L);
            flood((void *)2L);
            pthread_join(writer, NULL);
        } else if (!strcmp(argv[1], "live")) {
            put(1, "To sign in, visit https://microsoft.com/devicelogin and enter code ABCD-1234");
            put(2, "Waiting for authentication");
            for (int i = 0; i < 200; ++i) {
                if (access(argv[2], F_OK) == 0) return 0;
                usleep(10000);
            }
            return 23;
        } else if (!strcmp(argv[1], "utf8")) {
            const unsigned char text[] = "開始🙂\r50%\r\nDone 終";
            for (int i = 0; i < sizeof(text) - 1; ++i) {
                write(1, text + i, 1);
                usleep(15000);
            }
        } else if (!strcmp(argv[1], "secrets")) {
            put(1, "https://fixture.blob.core.windows.net/c?si"); usleep(30000);
            put(1, "g=UNKNOWN_"); usleep(30000);
            put(1, "SIGNATURE&sp=r\n--source-"); usleep(30000);
            put(1, "sas "); usleep(30000);
            put(1, "sv=1&sig=FLAG_SIGNATURE\n");
            put(2, "AZCOPY_SPA_CLIENT_"); usleep(30000);
            put(2, "SECRET=\"QUOTED "); usleep(30000);
            put(2, "SECRET\"\nknown multi"); usleep(30000);
            put(2, "word credential\n");
        } else if (!strcmp(argv[1], "secret-boundaries")) {
            put(1, "https://fixture.blob.core.windows.net/c?\\u0073\\u0069"); usleep(30000);
            put(1, "\\u0067\\u003dENCODED_"); usleep(30000);
            put(1, "SECRET\nAuthorization: Bearer HEADER_SECRET\nunfinished");
            put(2, "AZCOPY_SPA_CLIENT_SECRET=\"QUOTED_"); usleep(30000);
            put(2, "UNFINISHED");
        } else if (!strcmp(argv[1], "oversized-secret")) {
            put(1, "sig=");
            char block[1024]; memset(block, 'Z', sizeof(block));
            for (int i = 0; i < 256; ++i) write(1, block, sizeof(block));
            put(1, "\ncomplete\n");
        } else if (!strcmp(argv[1], "graceful") || !strcmp(argv[1], "resist")) {
            int resist = !strcmp(argv[1], "resist");
            signal(SIGINT, resist ? SIG_IGN : stop);
            signal(SIGTERM, resist ? SIG_IGN : stop);
            char message[80]; snprintf(message, sizeof(message), "%d READY", getpid());
            put(1, message);
            for (int i = 0; i < 300 && !interrupted; ++i) usleep(10000);
            if (interrupted) put(2, "Stopped cleanly\n");
        } else if (!strcmp(argv[1], "stdin")) {
            char input;
            if (read(0, &input, 1) == 0) put(1, "stdin closed\n");
            else return 12;
        } else if (!strcmp(argv[1], "touch")) {
            int fd = open(argv[2], O_CREAT | O_WRONLY, 0600);
            if (fd >= 0) close(fd);
        } else if (!strcmp(argv[1], "failure")) {
            put(2, "fixture failure\n"); return 7;
        } else if (!strcmp(argv[1], "echo") && argc > 2) {
            put(1, argv[2]); put(1, "\n");
        } else return 3;
        return 0;
    }
    """#
}
