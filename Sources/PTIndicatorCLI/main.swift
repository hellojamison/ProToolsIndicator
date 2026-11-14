import Foundation
import IndicatorCore

func usage() -> Never {
    let help = """
    Usage:
      pt-indicator request [--minutes <1-1440>] <agent-and-chat-title>
      pt-indicator wait <ticket>
      pt-indicator eta <ticket> <minutes|unknown>
      pt-indicator release <ticket> --closeout <outcome> [--reason "why the session must stay open"]
      pt-indicator cancel <ticket>
      pt-indicator status
      pt-indicator check-session

    Identify yourself and include the exact current chat title, for example:
      pt-indicator request --minutes 5 "Codex: Improve menu bar icon"
    Request only when you are ready to use Pro Tools: finish builds and prep first,
    and release during long rebuilds. --minutes is hands-on Pro Tools time only.
    A specific --reason (8-280 characters) is required for either left-open closeout outcome.
    Closed outcomes (no-session, saved-and-closed, no-save-needed-and-closed) are checked:
    if Pro Tools is running, it is asked read-only whether a session is open, and the
    release is refused while one is. Override the checker with PT_INDICATOR_SESSION_PROBE.
    """
    FileHandle.standardError.write(Data((help + "\n").utf8))
    exit(2)
}

func fail(_ error: Error) -> Never {
    fputs("pt-indicator: \(error.localizedDescription)\n", stderr)
    exit(1)
}

func printStatus(_ status: IndicatorStatus) {
    if status.inUse {
        print("Current agent: \(status.who ?? "Unknown")")
        if let minutes = status.activeEstimatedMinutes {
            print("Current ETA: about \(minutes) min remaining (agent estimate)")
        } else {
            print("Current ETA: not reported")
        }
        if let ticket = status.activeTicket {
            print("Active ticket: \(ticket)")
        }
    } else {
        print("Current agent: none (available)")
        let running = ProToolsDetector.running()
        if !running.isEmpty {
            let names = running.map(\.name).joined(separator: ", ")
            let verb = running.count == 1 ? "is" : "are"
            let lastHolder = status.lastCloseout?.releasedBy.map { "; last holder: \($0)" } ?? ""
            print("\(names) \(verb) running with no turn holder (left over?)\(lastHolder)")
        }
    }

    if status.queue.isEmpty {
        print("Waiting queue: empty")
    } else {
        print("Waiting queue:")
        var minutesUntilStart: Int? = status.inUse ? status.activeEstimatedMinutes : 0
        for (index, request) in status.queue.enumerated() {
            let startETA = minutesUntilStart.map { "about \($0) min" } ?? "unknown"
            let useEstimate = request.estimatedMinutes.map { "\($0) min use estimate" } ?? "no use estimate"
            print("\(index + 1). \(request.who) (starts in \(startETA); \(useEstimate); ticket: \(request.ticket))")
            if let current = minutesUntilStart, let duration = request.estimatedMinutes {
                minutesUntilStart = current + duration
            } else {
                minutesUntilStart = nil
            }
        }
    }

    if let report = status.lastCloseout {
        let owner = report.releasedBy ?? "Unknown"
        let timestamp = ISO8601DateFormatter().string(from: report.releasedAt)
        print("Last closeout: \(owner) — \(report.summary) (\(timestamp))")
    }
}

/// Asks Pro Tools, read-only via PTSL, whether a session is open. Never blocks more than ~11 s.
func runSessionProbe(timeout: TimeInterval = 10) -> SessionProbeResult {
    let environmentPath = ProcessInfo.processInfo.environment["PT_INDICATOR_SESSION_PROBE"]
    let path = (environmentPath?.isEmpty == false) ? environmentPath! : SessionProbe.defaultExecutablePath
    guard FileManager.default.isExecutableFile(atPath: path) else {
        return .failed("session check tool not found at \(path)")
    }

    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("pt-indicator-probe-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    } catch {
        return .failed("could not prepare session check: \(error.localizedDescription)")
    }
    defer { try? FileManager.default.removeItem(at: scratch) }
    let stdoutURL = scratch.appendingPathComponent("stdout")
    let stderrURL = scratch.appendingPathComponent("stderr")
    FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
    FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["current-session-path"]
    process.standardInput = FileHandle.nullDevice
    do {
        process.standardOutput = try FileHandle(forWritingTo: stdoutURL)
        process.standardError = try FileHandle(forWritingTo: stderrURL)
        try process.run()
    } catch {
        return .failed("could not start session check: \(error.localizedDescription)")
    }

    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    var timedOut = false
    if process.isRunning {
        timedOut = true
        process.terminate()
        let killDeadline = Date().addingTimeInterval(1)
        while process.isRunning && Date() < killDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    let stdoutText = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
    let stderrText = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
    return SessionProbe.interpret(
        exitCode: process.isRunning ? nil : process.terminationStatus,
        stdout: stdoutText,
        stderr: stderrText,
        timedOut: timedOut
    )
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { usage() }

switch command {
case "request":
    var requestArguments = Array(arguments.dropFirst())
    var estimatedMinutes: Int?
    if requestArguments.first == "--minutes" {
        guard requestArguments.count >= 3,
              let minutes = Int(requestArguments[1]),
              (1...1440).contains(minutes) else { usage() }
        estimatedMinutes = minutes
        requestArguments.removeFirst(2)
    }
    guard !requestArguments.isEmpty else { usage() }
    let who = requestArguments.joined(separator: " ")
    do {
        let result = try IndicatorStore.request(who: who, estimatedMinutes: estimatedMinutes)
        let estimate = estimatedMinutes.map { " estimate=\($0)m" } ?? ""
        if result.position == 0 {
            print("granted\(estimate) ticket=\(result.ticket)")
        } else {
            print("queued position=\(result.position)\(estimate) ticket=\(result.ticket)")
        }
    } catch {
        fail(error)
    }

case "wait":
    guard arguments.count == 2 else { usage() }
    let ticket = arguments[1]
    while true {
        let status = IndicatorStore.read()
        if status.activeTicket == ticket {
            print("granted ticket=\(ticket)")
            break
        }
        guard status.queue.contains(where: { $0.ticket == ticket }) else {
            fputs("pt-indicator: queue ticket was canceled or does not exist\n", stderr)
            exit(3)
        }
        Thread.sleep(forTimeInterval: 1)
    }

case "eta":
    guard arguments.count == 3 else { usage() }
    let ticket = arguments[1]
    let minutes: Int?
    if arguments[2] == "unknown" {
        minutes = nil
    } else if let parsed = Int(arguments[2]) {
        minutes = parsed
    } else {
        usage()
    }
    do {
        try IndicatorStore.updateETA(ticket: ticket, minutes: minutes)
        printStatus(IndicatorStore.read())
    } catch {
        fail(error)
    }

case "release":
    guard arguments.count == 4 || arguments.count == 6,
          arguments[2] == "--closeout",
          let closeout = SessionCloseout(rawValue: arguments[3]) else { usage() }
    var reason: String?
    if arguments.count == 6 {
        guard arguments[4] == "--reason" else { usage() }
        reason = arguments[5]
    }
    let ticket = arguments[1]
    do {
        _ = try IndicatorStore.validatedReason(reason, for: closeout)
        // Fail fast before probing if this ticket does not hold the turn; release re-checks under the lock.
        guard IndicatorStore.read().activeTicket == ticket else {
            throw IndicatorStoreError.ticketDoesNotOwnTurn
        }

        // The session check runs outside the queue lock so other agents are never blocked on it.
        let proToolsRunning = !ProToolsDetector.running().isEmpty
        let probe: SessionProbeResult? = (closeout.claimsClosed && proToolsRunning) ? runSessionProbe() : nil
        switch ReleaseGate.decide(outcome: closeout, proToolsRunning: proToolsRunning, probe: probe) {
        case .refuse(let path):
            fputs("pt-indicator: \(ReleaseGate.refusalMessage(openSessionPath: path, outcome: closeout))\n", stderr)
            exit(4)
        case .accept(let verification, let note):
            if verification == .notVerified {
                fputs("pt-indicator: warning: could not verify that no session is open (\(note ?? "unknown")); releasing with closure marked not verified.\n", stderr)
            }
            try IndicatorStore.release(
                ticket: ticket,
                closeout: closeout,
                reason: reason,
                verification: verification,
                verificationNote: note
            )
        }
        printStatus(IndicatorStore.read())
    } catch {
        fail(error)
    }

case "cancel":
    guard arguments.count == 2 else { usage() }
    do {
        guard try IndicatorStore.cancel(ticket: arguments[1]) else {
            throw IndicatorStoreError.ticketNotFound
        }
        print("Queue request canceled")
    } catch {
        fail(error)
    }

case "check-session":
    // Read-only: reports whether Pro Tools has a session open, the same check release uses.
    guard arguments.count == 1 else { usage() }
    let running = ProToolsDetector.running()
    guard !running.isEmpty else {
        print("Pro Tools is not running; no session is open.")
        exit(0)
    }
    switch runSessionProbe() {
    case .sessionOpen(let path):
        print("Session open: \(path)")
        exit(5)
    case .noSession:
        print("\(running.map(\.name).joined(separator: ", ")) is running with no session open.")
    case .failed(let reason):
        fputs("pt-indicator: could not check for an open session (\(reason))\n", stderr)
        exit(6)
    }

case "status", "queue":
    guard arguments.count == 1 else { usage() }
    printStatus(IndicatorStore.read())

default:
    usage()
}
