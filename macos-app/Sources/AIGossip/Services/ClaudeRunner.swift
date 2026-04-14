import Foundation

/// Swift 6-safe one-shot gate around a CheckedContinuation.
/// The timer task and Process.terminationHandler both race to resume the
/// continuation; whoever wins first wins, the loser no-ops.
private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(
        _ cont: CheckedContinuation<String, Error>,
        with result: Result<String, Error>
    ) {
        lock.lock(); defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        switch result {
        case .success(let s): cont.resume(returning: s)
        case .failure(let e): cont.resume(throwing: e)
        }
    }
}

enum ClaudeRunnerError: Error, LocalizedError {
    case launchFailed(underlying: Error)
    case timedOut(seconds: Double)
    case nonZeroExit(code: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let err):
            return "claude 바이너리 실행 실패: \(err.localizedDescription)"
        case .timedOut(let s):
            return "claude -p 응답 없음 (\(Int(s))초 초과)"
        case .nonZeroExit(let code, let stderr):
            let snippet = stderr.prefix(200)
            return "claude -p exit \(code): \(snippet)"
        }
    }
}

/// Runs `claude -p` as a subprocess and returns its stdout.
/// GUI apps launched via `swift run` / Finder inherit a minimal PATH, so we
/// extend it with the usual install locations before invoking `env claude`.
actor ClaudeRunner {
    struct Options: Sendable {
        var binaryPath: String? = nil          // nil → resolve via `env`
        var timeout: TimeInterval = 120
        var maxRetries: Int = 1
        var extraPaths: [String] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            NSHomeDirectory() + "/.local/bin",
            NSHomeDirectory() + "/.volta/bin",
            NSHomeDirectory() + "/.claude/local",
        ]
    }

    private let options: Options
    private var activeProcess: Process?

    init(options: Options = .init()) {
        self.options = options
    }

    func run(prompt: String) async throws -> String {
        var lastError: Error?
        for attempt in 0...options.maxRetries {
            do { return try await runOnce(prompt: prompt) }
            catch {
                lastError = error
                if attempt < options.maxRetries {
                    let backoff = UInt64(500_000_000) << UInt64(attempt)
                    try? await Task.sleep(nanoseconds: backoff)
                }
            }
        }
        throw lastError ?? ClaudeRunnerError.timedOut(seconds: options.timeout)
    }

    /// Kill any in-flight `claude -p` subprocess. Called from
    /// `RoomService.shutdown()` during app termination so the child process
    /// doesn't outlive the GUI. No-op if no process is running.
    func cancelActive() {
        if let p = activeProcess, p.isRunning {
            p.terminate()
        }
        activeProcess = nil
    }

    // MARK: - Private

    private func runOnce(prompt: String) async throws -> String {
        let process = Process()
        activeProcess = process
        if let bin = options.binaryPath {
            process.executableURL = URL(fileURLWithPath: bin)
            process.arguments = ["-p"]
        } else {
            // `/usr/bin/env` is guaranteed to exist; we hand it an enriched PATH.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["claude", "-p"]
        }

        var env = ProcessInfo.processInfo.environment
        let existing = env["PATH"] ?? ""
        let combined = (options.extraPaths + [existing])
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        env["PATH"] = combined
        process.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ClaudeRunnerError.launchFailed(underlying: error)
        }

        // Feed the prompt on a background thread so we don't stall on large inputs.
        Task.detached {
            let handle = stdinPipe.fileHandleForWriting
            try? handle.write(contentsOf: Data(prompt.utf8))
            try? handle.close()
        }

        return try await waitForExit(
            process: process,
            stdout: stdoutPipe,
            stderr: stderrPipe
        )
    }

    private func waitForExit(
        process: Process,
        stdout: Pipe,
        stderr: Pipe
    ) async throws -> String {
        let timeout = options.timeout
        // Guard so timer vs terminationHandler never both resume the continuation.
        let gate = ContinuationGate()
        return try await withCheckedThrowingContinuation { cont in
            let timer = DispatchWorkItem {
                if process.isRunning { process.terminate() }
                gate.resume(cont, with: .failure(ClaudeRunnerError.timedOut(seconds: timeout)))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

            process.terminationHandler = { proc in
                timer.cancel()
                let outData = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
                let errData = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
                let outStr = String(data: outData, encoding: .utf8) ?? ""
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    gate.resume(cont, with: .success(outStr.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    gate.resume(cont, with: .failure(ClaudeRunnerError.nonZeroExit(
                        code: proc.terminationStatus,
                        stderr: errStr
                    )))
                }
            }
        }
    }
}
