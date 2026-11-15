import AppKit

/// The running Pro Tools app. Pro Tools allows only one copy to run at a time.
public struct RunningProTools: Identifiable, Equatable, Sendable {
    public let processIdentifier: Int32
    public let name: String

    public var id: Int32 { processIdentifier }
}

public enum ProToolsDetector {
    private static let bundleIdentifiers: Set<String> = [
        "com.avid.ProTools",
        "com.avid.ProToolsDeveloper",
    ]

    public static func detect(in applications: [NSRunningApplication]) -> RunningProTools? {
        applications.lazy.compactMap { application -> RunningProTools? in
            guard let identifier = application.bundleIdentifier,
                  bundleIdentifiers.contains(identifier) || identifier.hasPrefix("com.avid.ProTools.") else {
                return nil
            }

            return RunningProTools(
                processIdentifier: application.processIdentifier,
                name: displayName(for: application)
            )
        }
        .first
    }

    /// The running Pro Tools app right now, if any (same detection the menu bar app uses).
    public static func running() -> RunningProTools? {
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
