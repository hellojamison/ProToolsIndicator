import AppKit
import Combine
import IndicatorCore
import SwiftUI

@MainActor
final class IndicatorModel: ObservableObject {
    @Published private(set) var status = IndicatorStore.read()
    private var timer: AnyCancellable?

    init() {
        timer = Timer.publish(every: 0.35, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.status = IndicatorStore.read() }
    }

    func set(inUse: Bool) {
        try? IndicatorStore.set(inUse: inUse)
        status = IndicatorStore.read()
    }
}

@main
struct ProToolsIndicatorApp: App {
    @StateObject private var model = IndicatorModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            Text(model.status.inUse ? "An agent is using Pro Tools" : "Pro Tools is available")
                .disabled(true)
            Divider()
            Button("Mark In Use") { model.set(inUse: true) }
                .disabled(model.status.inUse)
            Button("Mark Available") { model.set(inUse: false) }
                .disabled(!model.status.inUse)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(model.status.inUse ? Color.red : Color.green)
                    .frame(width: 9, height: 9)
                Text("PT")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .accessibilityLabel(model.status.inUse ? "Pro Tools in use" : "Pro Tools available")
        }
        .menuBarExtraStyle(.menu)
    }
}
