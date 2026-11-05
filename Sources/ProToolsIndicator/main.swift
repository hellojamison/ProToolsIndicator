import AppKit
import Combine
import IndicatorCore
import SwiftUI

@MainActor
final class IndicatorModel: ObservableObject {
    @Published private(set) var status = IndicatorStore.read()
    @Published var enteredName = ""
    @Published var estimateText = ""
    @Published private(set) var message: String?
    private var timer: AnyCancellable?

    init() {
        timer = Timer.publish(every: 0.35, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.status = IndicatorStore.read()
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

    func releaseCurrent() {
        do {
            try IndicatorStore.releaseCurrent()
            refresh()
            message = status.inUse
                ? "Turn passed to \(status.who ?? "the next person")."
                : "Pro Tools is available."
        } catch {
            message = error.localizedDescription
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
        model.status.inUse
            ? Color(red: 0.84, green: 0.00, blue: 0.10)
            : Color(red: 0.03, green: 0.48, blue: 0.13)
    }

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.status.inUse ? "PRO TOOLS IN USE" : "PRO TOOLS AVAILABLE")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(statusColor)

                if model.status.inUse {
                    let estimate = model.status.activeEstimatedMinutes.map { " · about \($0) min" } ?? ""
                    Text("Currently using: \(model.status.who ?? "Unknown")\(estimate)")
                        .font(.system(size: 12, weight: .semibold))
                }

                TextField("Your name or agent", text: $model.enteredName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.requestAccess() }

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
                    Button("Release and Call Next") { model.releaseCurrent() }
                }

                if !model.status.queue.isEmpty {
                    Divider()
                    Text("WAITING QUEUE · \(model.status.queue.count)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                    ForEach(model.status.queue.indices, id: \.self) { index in
                        let request = model.status.queue[index]
                        let estimate = request.estimatedMinutes.map { "\($0) min" } ?? "no estimate"
                        HStack(spacing: 6) {
                            Text("\(index + 1). \(request.who) · \(estimate)")
                                .lineLimit(1)
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
        } label: {
            Group {
                if model.status.inUse {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(.white)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(.black.opacity(0.28), lineWidth: 1))
                        Text(menuBarText)
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(statusColor, in: Capsule())
                    .accessibilityLabel(accessibilityStatus)
                } else {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(.black.opacity(0.3), lineWidth: 1))
                        .padding(.horizontal, 4)
                        .accessibilityLabel(accessibilityStatus)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarText: String {
        guard model.status.inUse else { return "AVAILABLE" }
        let waiting = model.status.queue.count
        return waiting == 0 ? "IN USE" : "IN USE · \(waiting)"
    }

    private var accessibilityStatus: String {
        guard model.status.inUse else { return "Pro Tools available" }
        let waiting = model.status.queue.count
        return waiting == 0
            ? "Pro Tools in use"
            : "Pro Tools in use, \(waiting) waiting in queue"
    }
}
