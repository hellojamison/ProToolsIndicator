import AppKit
import Combine
import IndicatorCore
import SwiftUI

struct RunningProToolsVersion: Identifiable, Equatable {
    let processIdentifier: Int32
    let name: String

    var id: Int32 { processIdentifier }
}

enum ProToolsDetector {
    private static let bundleIdentifiers: Set<String> = [
        "com.avid.ProTools",
        "com.avid.ProToolsDeveloper",
    ]

    static func detect(in applications: [NSRunningApplication]) -> [RunningProToolsVersion] {
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

@MainActor
final class IndicatorModel: ObservableObject {
    @Published private(set) var status = IndicatorStore.read()
    @Published private(set) var openProToolsVersions = ProToolsDetector.detect(
        in: NSWorkspace.shared.runningApplications
    )
    @Published var enteredName = ""
    @Published var estimateText = ""
    @Published private(set) var message: String?
    @Published var showingCloseout = false
    @Published private(set) var pendingCloseout: SessionCloseout?
    @Published var closeoutReason = ""
    private var timer: AnyCancellable?
    private var runningApplicationsObserver: AnyCancellable?

    init() {
        timer = Timer.publish(every: 0.35, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.status = IndicatorStore.read()
            }

        runningApplicationsObserver = NSWorkspace.shared.publisher(for: \.runningApplications)
            .receive(on: RunLoop.main)
            .sink { [weak self] applications in
                self?.openProToolsVersions = ProToolsDetector.detect(in: applications)
            }
    }

    var canMarkInUse: Bool {
        !enteredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (estimateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || estimatedMinutes != nil)
    }

    var estimatedMinutes: Int? {
        let input = estimateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty,
              let minutes = Int(input),
              (1...1440).contains(minutes) else {
            return nil
        }
        return minutes
    }

    func queueStartETAMinutes(for index: Int) -> Int? {
        guard status.queue.indices.contains(index) else { return nil }
        var eta = status.inUse ? status.activeEstimatedMinutes : 0
        if status.inUse && eta == nil { return nil }
        for priorIndex in 0..<index {
            guard let currentETA = eta,
                  let duration = status.queue[priorIndex].estimatedMinutes else {
                return nil
            }
            eta = currentETA + duration
        }
        return eta
    }

    func requestAccess() {
        let who = enteredName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !who.isEmpty else { return }
        if !estimateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           estimatedMinutes == nil {
            message = "Estimated time must be a whole number from 1 to 1440 minutes."
            return
        }
        do {
            let estimate = estimatedMinutes
            let result = try IndicatorStore.request(who: who, estimatedMinutes: estimate)
            enteredName = ""
            estimateText = ""
            refresh()
            let estimateDescription = estimate.map { " Estimated: \($0) min." } ?? ""
            message = result.position == 0
                ? "Your turn is ready.\(estimateDescription) Ticket: \(result.ticket)"
                : "Queued at position \(result.position).\(estimateDescription) Ticket: \(result.ticket)"
        } catch {
            message = error.localizedDescription
        }
    }

    var canConfirmCloseout: Bool {
        (8...280).contains(closeoutReason.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }

    func beginCloseout(closeout: SessionCloseout) {
        guard closeout.requiresReason else {
            _ = releaseCurrent(closeout: closeout)
            return
        }
        closeoutReason = ""
        pendingCloseout = closeout
    }

    func confirmCloseout() {
        guard let pendingCloseout, canConfirmCloseout else { return }
        guard releaseCurrent(closeout: pendingCloseout, reason: closeoutReason) else { return }
        self.pendingCloseout = nil
        closeoutReason = ""
    }

    func cancelCloseoutReason() {
        pendingCloseout = nil
        closeoutReason = ""
    }

    @discardableResult
    private func releaseCurrent(closeout: SessionCloseout, reason: String? = nil) -> Bool {
        do {
            try IndicatorStore.releaseCurrent(closeout: closeout, reason: reason)
            refresh()
            message = status.inUse
                ? "Turn passed to \(status.who ?? "the next person")."
                : "Pro Tools is available."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func removeQueued(ticket: String) {
        do {
            _ = try IndicatorStore.cancel(ticket: ticket)
            refresh()
        } catch {
            message = error.localizedDescription
        }
    }

    private func refresh() {
        status = IndicatorStore.read()
    }
}

@main
struct ProToolsIndicatorApp: App {
    @StateObject private var model = IndicatorModel()

    private var statusColor: Color {
        if model.status.inUse {
            return Color(red: 0.84, green: 0.00, blue: 0.10)
        }
        return Color(red: 0.03, green: 0.48, blue: 0.13)
    }

    private var menuBarStatusImage: NSImage {
        let color: NSColor
        if model.status.inUse {
            color = NSColor(calibratedRed: 0.98, green: 0.08, blue: 0.18, alpha: 1)
        } else {
            color = NSColor(calibratedRed: 0.05, green: 0.82, blue: 0.22, alpha: 1)
        }

        let image = NSImage(size: NSSize(width: 15, height: 15))
        image.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 15, height: 15)).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 11, height: 11)).fill()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 7, height: 7)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 10) {
                Text(statusHeading)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(statusColor)

                Divider()
                Text("CURRENT AGENT")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                Text(model.status.inUse ? (model.status.who ?? "Unknown") : "None")
                    .font(.system(size: 12, weight: .semibold))
                Text(model.status.inUse
                     ? model.status.activeEstimatedMinutes.map { "ETA from agent: about \($0) min remaining" } ?? "ETA from agent: not reported"
                     : "No active agent")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                if !model.openProToolsVersions.isEmpty {
                    Text("OPEN PRO TOOLS VERSIONS")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                    ForEach(model.openProToolsVersions) { version in
                        Text(version.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                }

                if let report = model.status.lastCloseout {
                    Text("LAST HANDOFF")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                    Text("\(report.releasedBy ?? "Unknown"): \(report.summary)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField("Agent: exact chat title", text: $model.enteredName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.requestAccess() }
                Text("Include your agent name and current chat title so status identifies this conversation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Estimated Pro Tools time (minutes)", text: $model.estimateText)
                    .textFieldStyle(.roundedBorder)

                if !model.estimateText.isEmpty && model.estimatedMinutes == nil {
                    Text("Enter a whole number from 1 to 1440.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red)
                }

                Button(model.status.inUse || !model.status.queue.isEmpty ? "Join Queue" : "Request Pro Tools") {
                    model.requestAccess()
                }
                .disabled(!model.canMarkInUse)

                if model.status.inUse {
                    Button("Release and Call Next") { model.showingCloseout = true }
                }

                if let pendingCloseout = model.pendingCloseout {
                    Divider()
                    Text(pendingCloseout == .leftOpenNeedsSave
                         ? "Why does this session need to stay open?"
                         : "Why must this session stay open?")
                        .font(.system(size: 11, weight: .semibold))
                    TextField("Specific reason (8–280 characters)", text: $model.closeoutReason)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.confirmCloseout() }
                    HStack {
                        Button("Cancel") { model.cancelCloseoutReason() }
                        Spacer()
                        Button("Release turn") { model.confirmCloseout() }
                            .disabled(!model.canConfirmCloseout)
                    }
                }

                Divider()
                Text("QUEUE · \(model.status.queue.count)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                if model.status.queue.isEmpty {
                    Text("No agents waiting")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.status.queue.indices, id: \.self) { index in
                        let request = model.status.queue[index]
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(index + 1). \(request.who)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                let startETA = model.queueStartETAMinutes(for: index).map { "starts in about \($0) min" } ?? "start ETA unknown"
                                let useEstimate = request.estimatedMinutes.map { "use about \($0) min" } ?? "use estimate unknown"
                                Text("\(startETA) · \(useEstimate)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Button("Remove") { model.removeQueued(ticket: request.ticket) }
                                .controlSize(.small)
                        }
                    }
                    Text("Shorter estimates go first; ties stay FIFO. Requests without an estimate follow estimated requests.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                if let message = model.message {
                    Text(message)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Divider()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .padding(12)
            .frame(width: 260)
            .confirmationDialog(
                "Close out your Pro Tools turn",
                isPresented: $model.showingCloseout,
                titleVisibility: .visible
            ) {
                Button("No Session Open") { model.beginCloseout(closeout: .noSession) }
                Button("Saved and Closed") { model.beginCloseout(closeout: .savedAndClosed) }
                Button("No Save Needed; Closed") { model.beginCloseout(closeout: .noSaveNeededAndClosed) }
                Button("Left Open; Needs Saving") { model.beginCloseout(closeout: .leftOpenNeedsSave) }
                Button("Left Open; No Save Needed") { model.beginCloseout(closeout: .leftOpenNoSaveNeeded) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Save needed work, close sessions you opened, and verify they are closed before release. Preserve other people's sessions and uncertain unsaved work. Leaving a session open requires a specific reason. Be kind, rewind.")
            }
        } label: {
            HStack(spacing: 6) {
                Image(nsImage: menuBarStatusImage)
                Text("PT")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .offset(y: -1)
            }
            .padding(.horizontal, 4)
                .accessibilityLabel(accessibilityStatus)
        }
        .menuBarExtraStyle(.window)
    }

    private var statusHeading: String {
        if model.status.inUse { return "PRO TOOLS IN USE" }
        return model.openProToolsVersions.isEmpty ? "PRO TOOLS AVAILABLE" : "PRO TOOLS OPEN"
    }

    private var accessibilityStatus: String {
        guard model.status.inUse else {
            if model.openProToolsVersions.isEmpty { return "Pro Tools available" }
            let names = model.openProToolsVersions.map(\.name).joined(separator: ", ")
            return "Pro Tools open: \(names)"
        }
        let waiting = model.status.queue.count
        let reservation = waiting == 0
            ? "Pro Tools in use"
            : "Pro Tools in use, \(waiting) waiting in queue"
        guard !model.openProToolsVersions.isEmpty else { return reservation }
        return "\(reservation); open: \(model.openProToolsVersions.map(\.name).joined(separator: ", "))"
    }
}
