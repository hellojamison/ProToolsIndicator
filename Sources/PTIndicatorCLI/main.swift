import Foundation
import IndicatorCore

func usage() -> Never {
    let help = """
    Usage:
      pt-indicator request [--minutes <1-1440>] <who>
      pt-indicator wait <ticket>
      pt-indicator release <ticket>
      pt-indicator cancel <ticket>
      pt-indicator status
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
        print("Current: \(status.who ?? "Unknown")")
        if let minutes = status.activeEstimatedMinutes {
            print("Current estimate: \(minutes) min")
        }
        if let ticket = status.activeTicket {
            print("Active ticket: \(ticket)")
        }
    } else {
        print("Current: available")
    }

    if status.queue.isEmpty {
        print("Waiting queue: empty")
    } else {
        print("Waiting queue:")
        for (index, request) in status.queue.enumerated() {
            let estimate = request.estimatedMinutes.map { "\($0) min" } ?? "no estimate"
            print("\(index + 1). \(request.who) (\(estimate); ticket: \(request.ticket))")
        }
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

case "release":
    guard arguments.count == 2 else { usage() }
    do {
        try IndicatorStore.release(ticket: arguments[1])
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
