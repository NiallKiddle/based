// Based — turn your screen red. Menu bar only. macOS 13+.

import SwiftUI
import AppKit
import CoreGraphics
import ServiceManagement

// MARK: - Modes

enum Mode: String, CaseIterable, Identifiable {
    case day, night, off
    var id: String { rawValue }

    var title: String {
        switch self { case .day: "Day"; case .night: "Night"; case .off: "Off" }
    }
    var icon: String {
        switch self { case .day: "sun.max.fill"; case .night: "moon.fill"; case .off: "circle.slash" }
    }
    /// RGB multipliers applied to the display's gamma curve. nil = untouched.
    var rgb: (r: Float, g: Float, b: Float)? {
        switch self {
        case .day:   (1.0, 0.9, 0.4)     // yellow, still usable
        case .night: (1.0, 0.0, 0.0)     // pure red
        case .off:   nil
        }
    }
    var tint: [Color] {
        switch self {
        case .day:   [Color(red: 1.0, green: 0.85, blue: 0.30), Color(red: 0.95, green: 0.65, blue: 0.10)]
        case .night: [Color(red: 1.0, green: 0.25, blue: 0.22), Color(red: 0.72, green: 0.0, blue: 0.08)]
        case .off:   [Color(white: 0.45), Color(white: 0.30)]
        }
    }
}

// MARK: - Gamma (the part that actually turns the screen red)

enum Gamma {
    typealias Table = (r: [CGGammaValue], g: [CGGammaValue], b: [CGGammaValue])
    private static var originals: [CGDirectDisplayID: Table] = [:]

    static func displays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    private static func original(for d: CGDirectDisplayID) -> Table {
        if let t = originals[d] { return t }
        let cap = CGDisplayGammaTableCapacity(d)
        var r = [CGGammaValue](repeating: 0, count: Int(cap))
        var g = r, b = r
        var n: UInt32 = 0
        var t: Table
        if cap > 0, CGGetDisplayTransferByTable(d, cap, &r, &g, &b, &n) == .success, n > 0 {
            t = (Array(r.prefix(Int(n))), Array(g.prefix(Int(n))), Array(b.prefix(Int(n))))
        } else {
            let ramp = (0..<256).map { CGGammaValue($0) / 255 }
            t = (ramp, ramp, ramp)
        }
        originals[d] = t
        return t
    }

    static func apply(_ mode: Mode) {
        guard let k = mode.rgb else { reset(); return }
        for d in displays() {
            let o = original(for: d)
            CGSetDisplayTransferByTable(d, UInt32(o.r.count),
                                        o.r.map { $0 * k.r },
                                        o.g.map { $0 * k.g },
                                        o.b.map { $0 * k.b })
        }
    }

    /// Restore the system colour profile and forget cached curves.
    static func reset() {
        CGDisplayRestoreColorSyncSettings()
        originals.removeAll()
    }
}

// MARK: - State

final class Model: ObservableObject {
    static let shared = Model()
    private var timer: Timer?

    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Based: login item change failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    @Published var mode: Mode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "mode")
            Gamma.apply(mode)
        }
    }

    private init() {
        mode = Mode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "") ?? .off
        Gamma.reset()          // start from a clean profile
        Gamma.apply(mode)

        // macOS resets gamma on wake / display changes — put it back.
        let reapply: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            Gamma.reset()
            Gamma.apply(self.mode)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main, using: reapply)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                          object: nil, queue: .main, using: reapply)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                                          object: nil, queue: .main, using: reapply)
        // Belt and braces: other apps (Night Shift, colour pickers) can clobber it.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, self.mode != .off else { return }
            Gamma.apply(self.mode)
        }
    }
}

// MARK: - UI

struct Tile: View {
    let mode: Mode
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: mode.icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(mode.title)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(width: 70, height: 64)
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.75))
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected
                          ? AnyShapeStyle(LinearGradient(colors: mode.tint, startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color.primary.opacity(hover ? 0.10 : 0.05)))
                    .shadow(color: selected ? mode.tint.last!.opacity(0.45) : .clear, radius: 8, y: 3)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(selected ? 1.0 : (hover ? 0.98 : 0.96))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

struct Panel: View {
    @ObservedObject var model = Model.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Based")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(Mode.allCases) { m in
                    Tile(mode: m, selected: model.mode == m) { model.mode = m }
                }
            }
            HStack {
                Text("Open at login")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: Binding(get: { model.launchAtLogin },
                                         set: { model.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
            .padding(.top, 2)
        }
        .padding(14)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        _ = Model.shared
    }
    func applicationWillTerminate(_ n: Notification) {
        Gamma.reset()
    }
}

@main
struct BasedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject var model = Model.shared

    var body: some Scene {
        MenuBarExtra {
            Panel()
        } label: {
            Image(systemName: model.mode == .off ? "sun.max" : "sun.max.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
