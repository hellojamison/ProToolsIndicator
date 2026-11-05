import Foundation

public struct IndicatorStatus: Codable, Equatable, Sendable {
    public var inUse: Bool
    public var who: String?
    public var updatedAt: Date

    public init(inUse: Bool, who: String? = nil, updatedAt: Date = .now) {
        self.inUse = inUse
        self.who = who
        self.updatedAt = updatedAt
    }
}

public enum IndicatorStore {
    private static var statusURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("ProToolsIndicator", isDirectory: true)
            .appendingPathComponent("status.json")
    }

    public static func read() -> IndicatorStatus {
        guard let data = try? Data(contentsOf: statusURL),
              let status = try? JSONDecoder().decode(IndicatorStatus.self, from: data) else {
            return IndicatorStatus(inUse: false)
        }
        return status
    }

    public static func set(inUse: Bool, who: String? = nil) throws {
        let directory = statusURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(IndicatorStatus(inUse: inUse, who: inUse ? who : nil))
        try data.write(to: statusURL, options: .atomic)
    }
}
