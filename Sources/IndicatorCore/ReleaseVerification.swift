import Foundation

/// What the read-only session probe reported. The probe only asks Pro Tools
/// whether a session is open (PTSL GetSessionPath); it never reads session content.
public enum SessionProbeResult: Equatable, Sendable {
    case sessionOpen(path: String)
    case noSession
    /// The probe was missing, timed out or failed; the string says why.
    case failed(String)
}

/// How a closeout claim was checked when the turn was released.
public enum ClosureVerification: String, Codable, Equatable, Sendable {
    /// No Pro Tools application was running at release.
    case proToolsNotRunning = "pro-tools-not-running"
    /// Pro Tools was running and reported that no session was open.
    case noSessionOpen = "no-session-open"
    /// Pro Tools was running but the session check could not be completed.
    case notVerified = "not-verified"

    public var summary: String {
        switch self {
        case .proToolsNotRunning: "Verified: Pro Tools was not running."
        case .noSessionOpen: "Verified: Pro Tools reported no open session."
        case .notVerified: "Closure not verified."
        }
    }
}

public enum ReleaseDecision: Equatable, Sendable {
    /// Release the turn. `verification` is nil for left-open outcomes, which are not checked.
    case accept(verification: ClosureVerification?, note: String?)
    /// Keep the turn held: the closeout claims closed but a session is open.
    case refuse(openSessionPath: String)
}

public extension SessionCloseout {
    /// True for outcomes that claim no Pro Tools session remains open.
    var claimsClosed: Bool {
        switch self {
        case .noSession, .savedAndClosed, .noSaveNeededAndClosed: true
        case .leftOpenNeedsSave, .leftOpenNoSaveNeeded: false
        }
    }
}

public enum ReleaseGate {
    /// Pure decision for `release`: outcome × Pro Tools running × probe result.
    /// `probe` is only consulted when the outcome claims closed and Pro Tools is running;
    /// a nil probe there means the probe was not run, which counts as not verified.
    public static func decide(
        outcome: SessionCloseout,
        proToolsRunning: Bool,
        probe: SessionProbeResult?
    ) -> ReleaseDecision {
        guard outcome.claimsClosed else { return .accept(verification: nil, note: nil) }
        guard proToolsRunning else { return .accept(verification: .proToolsNotRunning, note: nil) }
        switch probe {
        case .sessionOpen(let path):
            return .refuse(openSessionPath: path)
        case .noSession:
            return .accept(verification: .noSessionOpen, note: nil)
        case .failed(let reason):
            return .accept(verification: .notVerified, note: reason)
        case nil:
            return .accept(verification: .notVerified, note: "session check was not run")
        }
    }

    public static func refusalMessage(openSessionPath path: String, outcome: SessionCloseout) -> String {
        """
        Release refused: you reported "\(outcome.rawValue)", but Pro Tools still has a session open:
          \(path)
        Your turn is still held. Close that session (and quit Pro Tools if you launched it), then release again.
        If it must stay open, release with --closeout left-open-needs-save or left-open-no-save-needed --reason "why".
        """
    }
}

public enum SessionProbe {
    /// Default probe: ptxExtractor's read-only `current-session-path` command.
    public static var defaultExecutablePath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Projects/ptxExtractor/Runtime/.build/debug/ptx-track-group-live-matrix")
            .path
    }

    /// Interprets the probe's output.
    /// Open session: exit 0 and JSON `{"session_path": "..."}`.
    /// No session: ptx-track-group-live-matrix exits 1 and prints its usage text
    /// (stderr starting `Usage:`), because `currentSessionPath()` returned nil and the
    /// command throws its usage error. Its other errors print their own message instead.
    /// Anything else is a failure, so closure counts as not verified.
    public static func interpret(
        exitCode: Int32?,
        stdout: String,
        stderr: String,
        timedOut: Bool
    ) -> SessionProbeResult {
        if timedOut { return .failed("session check timed out") }
        guard let exitCode else { return .failed("session check did not finish") }
        if exitCode == 0 {
            if let data = stdout.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let path = object["session_path"] as? String,
               !path.isEmpty {
                return .sessionOpen(path: path)
            }
            return .failed("session check returned unexpected output")
        }
        if exitCode == 1, stderr.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Usage:") {
            return .noSession
        }
        let firstLine = stderr.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let detail = firstLine.isEmpty ? "exit \(exitCode)" : "exit \(exitCode): \(firstLine.prefix(160))"
        return .failed("session check failed (\(detail))")
    }
}
