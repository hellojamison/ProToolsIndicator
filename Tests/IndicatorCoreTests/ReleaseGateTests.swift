import Foundation
import IndicatorCore
import Testing

@Suite struct ReleaseGateTests {
    static let closed: [SessionCloseout] = [.noSession, .savedAndClosed, .noSaveNeededAndClosed]
    static let leftOpen: [SessionCloseout] = [.leftOpenNeedsSave, .leftOpenNoSaveNeeded]

    @Test(arguments: closed)
    func closedClaimWithOpenSessionIsRefused(outcome: SessionCloseout) {
        let decision = ReleaseGate.decide(outcome: outcome, proToolsRunning: true, probe: .sessionOpen(path: "/tmp/A.ptx"))
        #expect(decision == .refuse(openSessionPath: "/tmp/A.ptx"))
    }

    @Test(arguments: closed)
    func closedClaimWithoutProToolsIsAccepted(outcome: SessionCloseout) {
        let decision = ReleaseGate.decide(outcome: outcome, proToolsRunning: false, probe: .sessionOpen(path: "/ignored"))
        #expect(decision == .accept(verification: .proToolsNotRunning, note: nil))
    }

    @Test(arguments: closed)
    func closedClaimWithNoSessionIsVerified(outcome: SessionCloseout) {
        let decision = ReleaseGate.decide(outcome: outcome, proToolsRunning: true, probe: .noSession)
        #expect(decision == .accept(verification: .noSessionOpen, note: nil))
    }

    @Test(arguments: closed)
    func probeFailureIsAcceptedButNotVerified(outcome: SessionCloseout) {
        let decision = ReleaseGate.decide(outcome: outcome, proToolsRunning: true, probe: .failed("session check timed out"))
        #expect(decision == .accept(verification: .notVerified, note: "session check timed out"))
        let missing = ReleaseGate.decide(outcome: outcome, proToolsRunning: true, probe: nil)
        #expect(missing == .accept(verification: .notVerified, note: "session check was not run"))
    }

    @Test(arguments: leftOpen)
    func leftOpenOutcomesAreNeverChecked(outcome: SessionCloseout) {
        for running in [true, false] {
            for probe: SessionProbeResult? in [nil, .noSession, .sessionOpen(path: "/x.ptx"), .failed("x")] {
                #expect(ReleaseGate.decide(outcome: outcome, proToolsRunning: running, probe: probe)
                    == .accept(verification: nil, note: nil))
            }
        }
    }

    @Test func interpretsOpenSession() {
        let result = SessionProbe.interpret(exitCode: 0, stdout: #"{"session_path":"\/Users\/a\/S.ptx"}"#, stderr: "", timedOut: false)
        #expect(result == .sessionOpen(path: "/Users/a/S.ptx"))
    }

    @Test func interpretsNoSessionUsageExit() {
        let result = SessionProbe.interpret(exitCode: 1, stdout: "", stderr: "Usage:\n  ptx-track-group-live-matrix create-protected-copy-certification-session NAME\n", timedOut: false)
        #expect(result == .noSession)
    }

    @Test func interpretsOtherFailuresAsUnverified() {
        #expect(SessionProbe.interpret(exitCode: 1, stdout: "", stderr: "connectionFailed\n", timedOut: false)
            == .failed("session check failed (exit 1: connectionFailed)"))
        #expect(SessionProbe.interpret(exitCode: nil, stdout: "", stderr: "", timedOut: true)
            == .failed("session check timed out"))
        #expect(SessionProbe.interpret(exitCode: 0, stdout: "garbage", stderr: "", timedOut: false)
            == .failed("session check returned unexpected output"))
    }

    @Test func unverifiedClosureShowsInSummary() {
        let report = SessionCloseoutReport(
            releasedBy: "Codex: X",
            outcome: .noSaveNeededAndClosed,
            verification: .notVerified,
            verificationNote: "session check timed out"
        )
        #expect(report.summary == "Session did not need saving; closed. Closure not verified. (session check timed out)")
    }

    @Test func oldStatusFilesStillDecode() throws {
        let json = #"{"releasedBy":"A","outcome":"no-session","releasedAt":0}"#
        let report = try JSONDecoder().decode(SessionCloseoutReport.self, from: Data(json.utf8))
        #expect(report.verification == nil)
    }
}
