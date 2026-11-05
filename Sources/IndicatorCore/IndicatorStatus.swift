import Darwin
import Foundation

public struct QueueRequest: Codable, Equatable, Identifiable, Sendable {
    public var ticket: String
    public var who: String
    public var estimatedMinutes: Int?
    public var requestedAt: Date

    public var id: String { ticket }

    public init(
        ticket: String,
        who: String,
        estimatedMinutes: Int? = nil,
        requestedAt: Date = .now
    ) {
        self.ticket = ticket
        self.who = who
        self.estimatedMinutes = estimatedMinutes
        self.requestedAt = requestedAt
    }
}

public struct IndicatorStatus: Codable, Equatable, Sendable {
    public var inUse: Bool
    public var who: String?
    public var activeTicket: String?
    public var activeEstimatedMinutes: Int?
    public var queue: [QueueRequest]
    public var updatedAt: Date

    public init(
        inUse: Bool,
        who: String? = nil,
        activeTicket: String? = nil,
        activeEstimatedMinutes: Int? = nil,
        queue: [QueueRequest] = [],
        updatedAt: Date = .now
    ) {
        self.inUse = inUse
        self.who = who
        self.activeTicket = activeTicket
        self.activeEstimatedMinutes = activeEstimatedMinutes
        self.queue = queue
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case inUse
        case who
        case activeTicket
        case activeEstimatedMinutes
        case queue
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        inUse = try values.decodeIfPresent(Bool.self, forKey: .inUse) ?? false
        who = try values.decodeIfPresent(String.self, forKey: .who)
        activeTicket = try values.decodeIfPresent(String.self, forKey: .activeTicket)
        activeEstimatedMinutes = try values.decodeIfPresent(Int.self, forKey: .activeEstimatedMinutes)
        queue = try values.decodeIfPresent([QueueRequest].self, forKey: .queue) ?? []
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }
}

public struct QueueRequestResult: Sendable {
    public let ticket: String
    /// Zero means the request was granted immediately; positive values are one-based queue positions.
    public let position: Int

    public init(ticket: String, position: Int) {
        self.ticket = ticket
        self.position = position
    }
}

public enum IndicatorStoreError: Error, LocalizedError {
    case emptyName
    case invalidEstimate
    case ticketDoesNotOwnTurn
    case ticketNotFound

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Enter a name before requesting Pro Tools."
        case .invalidEstimate:
            return "Estimated time must be a whole number of minutes from 1 to 1440."
        case .ticketDoesNotOwnTurn:
            return "That ticket does not own the current Pro Tools turn."
        case .ticketNotFound:
            return "That queue ticket is no longer waiting."
        }
    }
}

public enum IndicatorStore {
    private static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProToolsIndicator", isDirectory: true)
    }

    private static var statusURL: URL {
        supportDirectory.appendingPathComponent("status.json")
    }

    private static var lockURL: URL {
        supportDirectory.appendingPathComponent("status.lock")
    }

    public static func read() -> IndicatorStatus {
        readUnlocked()
    }

    public static func request(who: String, estimatedMinutes: Int? = nil) throws -> QueueRequestResult {
        let name = who.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw IndicatorStoreError.emptyName }
        if let estimatedMinutes, !(1...1440).contains(estimatedMinutes) {
            throw IndicatorStoreError.invalidEstimate
        }

        let ticket = UUID().uuidString.lowercased()
        let position = try withLockedStatus { status -> Int in
            if !status.inUse && status.queue.isEmpty {
                status.inUse = true
                status.who = name
                status.activeTicket = ticket
                status.activeEstimatedMinutes = estimatedMinutes
                return 0
            }

            let request = QueueRequest(
                ticket: ticket,
                who: name,
                estimatedMinutes: estimatedMinutes
            )
            let priority = estimatedMinutes ?? Int.max
            let insertionIndex = status.queue.firstIndex {
                ($0.estimatedMinutes ?? Int.max) > priority
            } ?? status.queue.endIndex
            status.queue.insert(request, at: insertionIndex)
            return insertionIndex + 1
        }
        return QueueRequestResult(ticket: ticket, position: position)
    }

    /// Releases a CLI-owned turn. A ticket is required when the current turn came from the CLI queue.
    public static func release(ticket: String? = nil) throws {
        try withLockedStatus { status in
            if status.activeTicket != ticket {
                throw IndicatorStoreError.ticketDoesNotOwnTurn
            }
            Self.advance(&status)
        }
    }

    /// Menu bar control for a person physically at the Mac.
    public static func releaseCurrent() throws {
        try withLockedStatus { status in
            Self.advance(&status)
        }
    }

    @discardableResult
    public static func cancel(ticket: String) throws -> Bool {
        try withLockedStatus { status in
            guard let index = status.queue.firstIndex(where: { $0.ticket == ticket }) else {
                return false
            }
            status.queue.remove(at: index)
            return true
        }
    }

    /// Allows a local user to mark Pro Tools in use without bypassing a waiting queue.
    @discardableResult
    public static func markInUseManually(who: String) throws -> Bool {
        let name = who.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw IndicatorStoreError.emptyName }

        return try withLockedStatus { status in
            guard !status.inUse, status.queue.isEmpty else { return false }
            status.inUse = true
            status.who = name
            status.activeTicket = nil
            status.activeEstimatedMinutes = nil
            return true
        }
    }

    private static func advance(_ status: inout IndicatorStatus) {
        if !status.queue.isEmpty {
            let next = status.queue.removeFirst()
            status.inUse = true
            status.who = next.who
            status.activeTicket = next.ticket
            status.activeEstimatedMinutes = next.estimatedMinutes
        } else {
            status.inUse = false
            status.who = nil
            status.activeTicket = nil
            status.activeEstimatedMinutes = nil
        }
    }

    private static func readUnlocked() -> IndicatorStatus {
        guard let data = try? Data(contentsOf: statusURL),
              let status = try? JSONDecoder().decode(IndicatorStatus.self, from: data) else {
            return IndicatorStatus(inUse: false)
        }
        return status
    }

    private static func withLockedStatus<Result>(
        _ update: (inout IndicatorStatus) throws -> Result
    ) throws -> Result {
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )

        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, mode_t(0o600))
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard flock(descriptor, LOCK_EX) == 0 else {
            let lockError = POSIXErrorCode(rawValue: errno) ?? .EIO
            Darwin.close(descriptor)
            throw POSIXError(lockError)
        }
        defer {
            _ = flock(descriptor, LOCK_UN)
            Darwin.close(descriptor)
        }

        var status = readUnlocked()
        let result = try update(&status)
        status.updatedAt = .now
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(status).write(to: statusURL, options: .atomic)
        return result
    }
}
