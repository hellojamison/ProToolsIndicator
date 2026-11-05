import Foundation
import IndicatorCore

func usage() -> Never {
    FileHandle.standardError.write(Data("Usage: pt-indicator on [who]|off|status\n".utf8))
    exit(2)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { usage() }

switch command {
case "on":
    let who = arguments.dropFirst().joined(separator: " ")
    do {
        try IndicatorStore.set(inUse: true, who: who.isEmpty ? nil : who)
        print(who.isEmpty ? "Pro Tools marked in use" : "Pro Tools marked in use by \(who)")
    } catch {
        fputs("Could not update indicator: \(error)\n", stderr)
        exit(1)
    }
case "off":
    guard arguments.count == 1 else { usage() }
    do {
        try IndicatorStore.set(inUse: false)
        print("Pro Tools marked available")
    } catch {
        fputs("Could not update indicator: \(error)\n", stderr)
        exit(1)
    }
case "status":
    guard arguments.count == 1 else { usage() }
    let status = IndicatorStore.read()
    if status.inUse, let who = status.who, !who.isEmpty {
        print("in-use by \(who)")
    } else {
        print(status.inUse ? "in-use" : "available")
    }
default:
    usage()
}
