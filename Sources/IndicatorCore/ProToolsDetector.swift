import AppKit

public struct RunningProToolsVersion: Identifiable, Equatable, Sendable {
    public let processIdentifier: Int32
    public let name: String

    public var id: Int32 { processIdentifier }
}

public enum ProToolsDetector {
    private static let bundleIdentifiers: Set<String> = [
        "com.avid.ProTools",
        "com.avid.ProToolsDeveloper",
    ]

    public static func detect(in applications: [NSRunningApplication]) -> [RunningProToolsVersion] {
        applications.compactMap { application in
            guard let identifier = application.bundleIdentifier,
                  bundleIdentifiers.contains(identifier) || identifier.hasPrefix("com.avid.ProTools.") else {
                return nil
            }

            return RunningProToolsVersion(
                processIdentifier: application.processIdentifier,
                name: displayName(for: application)
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Running Pro Tools applications right now (same detection the menu bar app uses).
    public static func running() -> [RunningProToolsVersion] {
        detect(in: NSWorkspace.shared.runningApplications)
    }

    private static func displayName(for application: NSRunningApplication) -> String {
        let bundleName = application.bundleURL?.deletingPathExtension().lastPathComponent
        if let bundleName,
           bundleName.localizedCaseInsensitiveContains("pro tools"),
           bundleName.localizedCaseInsensitiveCompare("Pro Tools") != .orderedSame {
            return bundleName
        }

        if let bundleURL = application.bundleURL,
           let version = Bundle(url: bundleURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            return "\(application.localizedName ?? "Pro Tools") \(version)"
        }

        return application.localizedName ?? bundleName ?? "Pro Tools"
    }
}
