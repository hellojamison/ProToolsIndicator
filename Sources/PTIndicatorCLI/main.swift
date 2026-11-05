import Foundation
import IndicatorCore

func usage() -> Never {
    let help = """
    Usage:
      pt-indicator request [--minutes <1-1440>] <agent-and-chat-title>
      pt-indicator wait <ticket>
      pt-indicator eta <ticket> <minutes|unknown>
      pt-indicator release <ticket> --closeout <no-session|saved-and-closed|no-save-needed-and-closed|left-open-needs-save|left-open-no-save-needed>
      pt-indicator cancel <ticket>
      pt-indicator status

    Identify yourself and include the exact current chat title, for example:
      pt-indicator request --minutes 5 "Codex: Improve menu bar icon"
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
        print("Last closeout: \(owner) — \(report.outcome.summary) (\(timestamp))")
    }
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
    guard arguments.count == 4,
          arguments[2] == "--closeout",
          let closeout = SessionCloseout(rawValue: arguments[3]) else { usage() }
    do {
        try IndicatorStore.release(ticket: arguments[1], closeout: closeout)
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

case "status", "queue":
    guard arguments.count == 1 else { usage() }
    printStatus(IndicatorStore.read())

default:
    usage()
}
