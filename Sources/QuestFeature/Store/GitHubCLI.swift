import Foundation

/// Real conformance, shelling out to the `gh` binary. Kept intentionally thin —
/// all decision logic (what counts as logged-out, how scopes split, what
/// `id` an account gets) lives in `GitHubAccountParsing.parseAccounts`, which
/// is pure and unit-tested. This type's only job is finding the binary and
/// running two commands.
public final class GitHubCLI: GitHubAccountSource, Sendable {
    /// Homebrew (Apple Silicon and Intel default prefixes) and the common
    /// system locations. Checked in order before falling back to `PATH`,
    /// because `Process` does not consult the shell's PATH resolution on its
    /// own the way a shell invocation would.
    private static let knownPaths = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/usr/bin/gh",
    ]

    private let binaryPath: String

    public init() throws {
        self.binaryPath = try Self.locateBinary()
    }

    private static func locateBinary() throws -> String {
        let fileManager = FileManager.default
        for path in knownPaths where fileManager.isExecutableFile(atPath: path) {
            return path
        }
        // Fall back to `PATH`, in case `gh` was installed somewhere else
        // (e.g. via mise/asdf, a custom prefix, or a non-Homebrew package
        // manager). `/usr/bin/which` is itself a fixed, always-present path,
        // so this does not reintroduce the "assume a path" problem.
        if let found = try? runProcess(executable: "/usr/bin/which", arguments: ["gh"]),
           found.exitCode == 0 {
            let path = found.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        throw GitHubCLIError.cliNotInstalled
    }

    public func accounts() throws -> [GitHubAccount] {
        let result = try Self.runProcess(executable: binaryPath, arguments: ["auth", "status", "--json", "hosts"])
        guard result.exitCode == 0 else {
            throw GitHubCLIError.commandFailed(stderr: Self.excerpt(result.stderr))
        }
        return try GitHubAccountParsing.parseAccounts(Data(result.stdout.utf8))
    }

    public func token(for account: GitHubAccount) throws -> String {
        let result = try Self.runProcess(
            executable: binaryPath,
            arguments: ["auth", "token", "--user", account.login, "--hostname", account.host]
        )
        guard result.exitCode == 0 else {
            // Never let a token leak into an error message — stderr from
            // `gh auth token` does not carry the secret, only diagnostics.
            throw GitHubCLIError.commandFailed(stderr: Self.excerpt(result.stderr))
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func excerpt(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
    }

    private struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// No explicit timeout: both commands are local reads (Keychain/config
    /// lookups), not network calls — `gh` does not hit the network to answer
    /// `auth status` or `auth token`. If that assumption ever proves wrong in
    /// practice, add a `waitUntilExit`-with-deadline here.
    private static func runProcess(executable: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
