import Foundation

/// Resolves the human (ideally Korean) name for the current macOS user.
///
/// Priority chain — first non-empty wins:
///   1. `dscl . -read /Users/$USER RealName`   — macOS account "Full name"
///   2. `git config user.name`                  — dev's git identity
///   3. `id -F`                                 — fallback to finger-style RealName
///   4. `NSUserName()`                          — raw short login name
///
/// We deliberately call out to Process here (no shell) because macOS
/// Directory Services isn't exposed as a public API; `dscl` is the
/// documented way to read RealName on modern macOS.
enum KoreanNameResolver {

    static func resolve() -> String {
        for candidate in [fromDscl(), fromGitConfig(), fromIdF()] {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return NSUserName()
    }

    // MARK: - Individual sources

    private static func fromDscl() -> String {
        // `dscl . -read /Users/$USER RealName` → "RealName:\n 최영기" or "RealName: 최영기"
        let raw = runCapturing(
            path: "/usr/bin/dscl",
            args: [".", "-read", "/Users/\(NSUserName())", "RealName"]
        ) ?? ""
        // Strip the "RealName:" prefix and any surrounding whitespace/newlines.
        let lines = raw.split(separator: "\n").map(String.init)
        // Case A: single line "RealName: 최영기"
        if let head = lines.first, head.contains("RealName:") {
            let inline = head.replacingOccurrences(of: "RealName:", with: "")
                .trimmingCharacters(in: .whitespaces)
            if !inline.isEmpty { return inline }
        }
        // Case B: two lines — "RealName:" then " 최영기"
        if lines.count >= 2 {
            return lines[1].trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    private static func fromGitConfig() -> String {
        runCapturing(path: "/usr/bin/env", args: ["git", "config", "--global", "user.name"]) ?? ""
    }

    private static func fromIdF() -> String {
        runCapturing(path: "/usr/bin/id", args: ["-F"]) ?? ""
    }

    // MARK: - Process helper

    private static func runCapturing(path: String, args: [String], timeout: TimeInterval = 2.0) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        // Give GUI apps a sane PATH — `git` is often only in homebrew.
        var env = ProcessInfo.processInfo.environment
        let existingPath = env["PATH"] ?? ""
        let extras = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        env["PATH"] = (extras + [existingPath]).filter { !$0.isEmpty }.joined(separator: ":")
        process.environment = env

        do {
            try process.run()
        } catch {
            return nil
        }

        // Wait with a short deadline so a hung subprocess can't stall the splash.
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            process.waitUntilExit()
            group.leave()
        }
        let result = group.wait(timeout: .now() + timeout)
        if result == .timedOut {
            if process.isRunning { process.terminate() }
            return nil
        }

        let data = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
