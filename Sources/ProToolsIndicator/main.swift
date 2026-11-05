import AppKit
import Combine
import IndicatorCore
import SwiftUI

@MainActor
final class IndicatorModel: ObservableObject {
    @Published private(set) var status = IndicatorStore.read()
    @Published var enteredName = IndicatorStore.read().who ?? ""
    private var timer: AnyCancellable?

    init() {
        timer = Timer.publish(every: 0.35, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let latest = IndicatorStore.read()
                if latest.who != self.status.who {
                    self.enteredName = latest.who ?? ""
                }
                self.status = latest
            }
    }

    var canMarkInUse: Bool {
        !enteredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func markInUse() {
        let who = enteredName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !who.isEmpty else { return }
        try? IndicatorStore.set(inUse: true, who: who)
        status = IndicatorStore.read()
    }

    func markAvailable() {
        try? IndicatorStore.set(inUse: false)
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

                if model.status.inUse, let who = model.status.who, !who.isEmpty {
                    Text("Currently using: \(who)")
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    Text("Who is using Pro Tools?")
                        .font(.system(size: 12, weight: .medium))
                }

                TextField("Name or agent", text: $model.enteredName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.markInUse() }

                HStack {
                    Button(model.status.inUse ? "Update User" : "Mark In Use") {
                        model.markInUse()
                    }
                    .disabled(!model.canMarkInUse)

                    if model.status.inUse {
                        Button("Mark Available") { model.markAvailable() }
                    }
                }

                Divider()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .padding(12)
            .frame(width: 260)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(.white)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(.black.opacity(0.28), lineWidth: 1))
                Text(model.status.inUse ? "IN USE" : "AVAILABLE")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(statusColor, in: Capsule())
            .accessibilityLabel(model.status.inUse ? "Pro Tools in use" : "Pro Tools available")
        }
        .menuBarExtraStyle(.window)
    }
}
