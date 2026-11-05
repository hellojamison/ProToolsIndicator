import Foundation
import IndicatorCore

func usage() -> Never {
    FileHandle.standardError.write(Data("Usage: pt-indicator on|off|status\n".utf8))
    exit(2)
}

guard CommandLine.arguments.count == 2 else { usage() }

switch CommandLine.arguments[1] {
case "on":
    do {
        try IndicatorStore.set(inUse: true)
        print("Pro Tools marked in use")
    } catch {
        fputs("Could not update indicator: \(error)\n", stderr)
        exit(1)
    }
case "off":
    do {
        try IndicatorStore.set(inUse: false)
        print("Pro Tools marked available")
    } catch {
        fputs("Could not update indicator: \(error)\n", stderr)
        exit(1)
    }
case "status":
    let status = IndicatorStore.read()
    print(status.inUse ? "in-use" : "available")
default:
    usage()
}
