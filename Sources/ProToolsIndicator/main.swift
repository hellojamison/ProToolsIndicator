import AppKit
import Combine
import IndicatorCore
import ServiceManagement
import SwiftUI

@MainActor
final class IndicatorModel: ObservableObject {
    @Published private(set) var status = IndicatorStore.read()
    @Published private(set) var openProTools = ProToolsDetector.detect(
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
                self?.openProTools = ProToolsDetector.detect(in: applications)
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

    // MARK: Open at login

    @Published private(set) var opensAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var loginItemNote: String?

    func refreshLoginItem() {
        let status = SMAppService.mainApp.status
        opensAtLogin = status == .enabled
        loginItemNote = status == .requiresApproval
            ? "Allow Pro Tools Indicator in System Settings > General > Login Items."
            : nil
    }

    func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginItem()
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            refreshLoginItem()
            loginItemNote = "Could not change Open at Login: \(error.localizedDescription)"
        }
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
            PopoverView(model: model)
                .onAppear { model.refreshLoginItem() }
        } label: {
            Image(nsImage: MenuBarLabel.image(inUse: model.status.inUse))
                .accessibilityLabel(accessibilityStatus)
        }
        .menuBarExtraStyle(.window)
    }

    private var accessibilityStatus: String {
        guard model.status.inUse else { return "Pro Tools available" }
        let waiting = model.status.queue.count
        return waiting == 0 ? "Pro Tools in use" : "Pro Tools in use, \(waiting) waiting"
    }
}

// MARK: - Menu bar label

/// Draws the status light and "PT" as one image so both share an exact vertical center.
enum MenuBarLabel {
    static func image(inUse: Bool) -> NSImage {
        let light = inUse
            ? NSColor(calibratedRed: 0.98, green: 0.08, blue: 0.18, alpha: 1)
            : NSColor(calibratedRed: 0.05, green: 0.82, blue: 0.22, alpha: 1)

        let font = NSFont.systemFont(ofSize: 13, weight: .bold)
        let text = "PT" as NSString
        let textWidth = ceil(text.size(withAttributes: [.font: font]).width)

        let dot: CGFloat = 15
        let gap: CGFloat = 4
        let height: CGFloat = 16
        let size = NSSize(width: dot + gap + textWidth, height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            let midY = height / 2
            let ring = NSRect(x: 0, y: midY - dot / 2, width: dot, height: dot)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: ring).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: ring.insetBy(dx: 2, dy: 2)).fill()
            light.setFill()
            NSBezierPath(ovalIn: ring.insetBy(dx: 4, dy: 4)).fill()

            // Center the capital letters on the light: put the baseline half a cap height below the
            // middle. CoreText draws at an exact baseline, unlike NSString.draw(at:).
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: text as String,
                attributes: [.font: font, .foregroundColor: NSColor.labelColor]
            ))
            context.textPosition = CGPoint(x: dot + gap, y: midY - font.capHeight / 2)
            CTLineDraw(line, context)
            return true
        }
        image.isTemplate = false
        return image
    }
}

// MARK: - Popover

enum Palette {
    static let inUse = Color(red: 1.00, green: 0.23, blue: 0.27)
    static let available = Color(red: 0.19, green: 0.82, blue: 0.35)
}

struct PopoverView: View {
    @ObservedObject var model: IndicatorModel

    private var tint: Color { model.status.inUse ? Palette.inUse : Palette.available }

    var body: some View {
        GlassGroup {
            VStack(alignment: .leading, spacing: 10) {
                statusCard
                if let pending = model.pendingCloseout {
                    reasonCard(for: pending)
                }
                if !model.status.queue.isEmpty {
                    queueCard
                }
                requestCard
                if let message = model.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 4)
                }
                footer
            }
            .padding(12)
        }
        .frame(width: 300)
        .confirmationDialog("How did you leave Pro Tools?", isPresented: $model.showingCloseout, titleVisibility: .visible) {
            Button("No session open") { model.beginCloseout(closeout: .noSession) }
            Button("Saved and closed") { model.beginCloseout(closeout: .savedAndClosed) }
            Button("Closed, nothing to save") { model.beginCloseout(closeout: .noSaveNeededAndClosed) }
            Button("Left open, needs saving") { model.beginCloseout(closeout: .leftOpenNeedsSave) }
            Button("Left open, nothing to save") { model.beginCloseout(closeout: .leftOpenNoSaveNeeded) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Save and close your session first. Be kind, rewind.")
        }
    }

    // Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                StatusDot(color: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.status.inUse ? "In Use" : "Available")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                if model.status.inUse, let minutes = model.status.activeEstimatedMinutes {
                    Pill(text: "\(minutes)m", systemImage: "clock")
                }
            }
            if model.status.inUse {
                Button {
                    model.showingCloseout = true
                } label: {
                    Label("Release", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .glassButton(prominent: true, tint: Palette.inUse)
            }
            if let report = model.status.lastCloseout {
                HandoffLine(report: report)
            }
        }
        .glassCard(tint: tint)
    }

    private var subtitle: String {
        if model.status.inUse { return model.status.who ?? "Unknown" }
        return model.openProTools?.name ?? "Pro Tools closed"
    }

    // Reason for leaving a session open

    private func reasonCard(for closeout: SessionCloseout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Why leave it open?")
                .font(.headline)
            TextField("Reason", text: $model.closeoutReason)
                .softField()
                .onSubmit { model.confirmCloseout() }
            HStack {
                Button("Cancel") { model.cancelCloseoutReason() }
                    .glassButton()
                Spacer()
                Button("Release") { model.confirmCloseout() }
                    .glassButton(prominent: true, tint: Palette.inUse)
                    .disabled(!model.canConfirmCloseout)
            }
        }
        .glassCard()
    }

    // Queue

    private var queueCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Up Next").font(.headline)
                Spacer()
                Text("\(model.status.queue.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(model.status.queue.enumerated()), id: \.element.ticket) { index, request in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .frame(width: 20, height: 20)
                        .background(.quaternary, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(request.who)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(queueDetail(index: index, request: request))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        model.removeQueued(ticket: request.ticket)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove")
                }
            }
        }
        .glassCard()
    }

    private func queueDetail(index: Int, request: QueueRequest) -> String {
        let start = model.queueStartETAMinutes(for: index).map { "in \($0)m" } ?? "in ?"
        let use = request.estimatedMinutes.map { "\($0)m" } ?? "?"
        return "\(start) · \(use)"
    }

    // Request

    private var requestCard: some View {
        let busy = model.status.inUse || !model.status.queue.isEmpty
        let badMinutes = !model.estimateText.isEmpty && model.estimatedMinutes == nil
        return HStack(spacing: 6) {
            TextField("Agent: chat title", text: $model.enteredName)
                .softField()
                .onSubmit { model.requestAccess() }
            TextField("min", text: $model.estimateText)
                .softField()
                .frame(width: 48)
                .foregroundStyle(badMinutes ? Palette.inUse : .primary)
                .help("Minutes in Pro Tools (1–1440)")
            Button {
                model.requestAccess()
            } label: {
                Image(systemName: busy ? "text.badge.plus" : "arrow.up")
                    .font(.body.weight(.semibold))
            }
            .glassButton(prominent: true, tint: .accentColor)
            .disabled(!model.canMarkInUse)
            .help(busy ? "Join queue" : "Request Pro Tools")
        }
        .glassCard()
    }

    // Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("Open at login", isOn: Binding(
                    get: { model.opensAtLogin },
                    set: { model.setOpensAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption)
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Quit")
            }
            if let note = model.loginItemNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Pieces

struct StatusDot: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.25)).frame(width: 30, height: 30)
            Circle()
                .fill(color.gradient)
                .frame(width: 14, height: 14)
                .shadow(color: color.opacity(0.9), radius: 6)
        }
    }
}

struct Pill: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassCapsule()
            .help("Agent's estimate of time left")
    }
}

struct HandoffLine: View {
    let report: SessionCloseoutReport

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
            Text("Last: \(outcome)")
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help("\(report.releasedBy ?? "Unknown"): \(report.summary)")
    }

    private var outcome: String {
        switch report.outcome {
        case .noSession: "no session"
        case .savedAndClosed: "saved & closed"
        case .noSaveNeededAndClosed: "closed"
        case .leftOpenNeedsSave: "left open, needs save"
        case .leftOpenNoSaveNeeded: "left open"
        }
    }

    private var icon: String {
        if report.outcome.requiresReason { return "exclamationmark.triangle.fill" }
        return report.verification == .notVerified ? "questionmark.circle" : "checkmark.seal.fill"
    }

    private var iconColor: Color {
        if report.outcome.requiresReason { return .orange }
        return report.verification == .notVerified ? .secondary : Palette.available
    }
}

// MARK: - Glass (Liquid Glass on macOS 26+, frosted material before)

struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 10) { content }
        } else {
            content
        }
    }
}

extension View {
    func softField() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    func glassCard(tint: Color? = nil) -> some View {
        modifier(GlassCardModifier(tint: tint))
    }

    func glassCapsule() -> some View {
        modifier(GlassCapsuleModifier())
    }

    func glassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        modifier(GlassButtonModifier(prominent: prominent, tint: tint))
    }
}

struct GlassCardModifier: ViewModifier {
    let tint: Color?

    func body(content: Content) -> some View {
        let padded = content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        if #available(macOS 26.0, *) {
            padded.glassEffect(
                tint.map { Glass.regular.tint($0.opacity(0.18)) } ?? .regular,
                in: .rect(cornerRadius: 18)
            )
        } else {
            padded
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .background((tint ?? .clear).opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct GlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.thinMaterial, in: Capsule())
        }
    }
}

struct GlassButtonModifier: ViewModifier {
    let prominent: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent).tint(tint)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            if prominent {
                content.buttonStyle(.borderedProminent).tint(tint)
            } else {
                content.buttonStyle(.bordered)
            }
        }
    }
}
