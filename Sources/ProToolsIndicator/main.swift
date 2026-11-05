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
            Text(model.status.inUse ? "PRO TOOLS IN USE" : "PRO TOOLS AVAILABLE")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(statusColor)
                .padding(.vertical, 2)
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
        .menuBarExtraStyle(.menu)
    }
}
