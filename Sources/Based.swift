// Based — turn your screen red. Lives in the menu bar. macOS 13+.

import SwiftUI
import AppKit
import CoreGraphics
import ServiceManagement
import Combine
import QuartzCore

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

private let panelRadius: CGFloat = 22

/// Real behind-window blur, clipped to a rounded rect.
struct Blur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        v.maskImage = Blur.mask(radius: panelRadius)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}

    static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let img = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        img.resizingMode = .stretch
        return img
    }
}

struct Tile: View {
    let mode: Mode
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: mode.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(mode.title)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.72))
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected
                          ? AnyShapeStyle(LinearGradient(colors: mode.tint, startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color.primary.opacity(hover ? 0.10 : 0.055)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(selected ? 0.28 : 0.06), lineWidth: 1)
                    }
                    .shadow(color: selected ? mode.tint.last!.opacity(0.5) : .clear, radius: 10, y: 4)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(selected ? 1.0 : (hover ? 0.985 : 0.965))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: selected)
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

struct Panel: View {
    @ObservedObject var model = Model.shared
    @State private var quitHover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Based")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(quitHover ? Color.primary : Color.secondary)
                    .onHover { quitHover = $0 }
            }
            HStack(spacing: 8) {
                ForEach(Mode.allCases) { m in
                    Tile(mode: m, selected: model.mode == m) { model.mode = m }
                }
            }
            HStack {
                Text("Open at login")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: Binding(get: { model.launchAtLogin },
                                         set: { model.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
        .padding(16)
        .frame(width: 280)
        .background(Blur())
        .overlay {
            RoundedRectangle(cornerRadius: panelRadius, style: .circular)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
    }
}

// MARK: - Menu bar item + floating panel

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    static func make(content: NSView) -> FloatingPanel {
        let p = FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        p.contentView = content
        p.setContentSize(content.fittingSize)
        return p
    }
}

final class StatusController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel: FloatingPanel
    private var monitors: [Any] = []
    private var modeObserver: Any?
    private var isShown = false

    override init() {
        panel = FloatingPanel.make(content: NSHostingView(rootView: Panel()))
        super.init()
        if let b = item.button {
            b.target = self
            b.action = #selector(toggle)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        setIcon(Model.shared.mode)
        modeObserver = Model.shared.$mode.sink { [weak self] m in
            DispatchQueue.main.async { self?.setIcon(m) }
        }
    }

    private func setIcon(_ mode: Mode) {
        let name = mode == .off ? "sun.max" : "sun.max.fill"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Based")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
        img?.isTemplate = true
        item.button?.image = img
    }

    @objc private func toggle() {
        isShown ? hide() : show()
    }

    private func show() {
        guard let button = item.button, let bw = button.window else { return }
        isShown = true
        let r = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        var x = r.midX - size.width / 2
        if let vf = (bw.screen ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        }
        let target = NSRect(x: x, y: r.minY - size.height - 6, width: size.width, height: size.height)

        panel.setFrame(target.offsetBy(dx: 0, dy: 8), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
        button.highlight(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.panel.invalidateShadow() }

        // Close on click anywhere else, or Esc.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.hide()
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            if e.keyCode == 53 { self?.hide(); return nil }
            return e
        }) { monitors.append(m) }
    }

    private func hide() {
        guard isShown else { return }
        isShown = false
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        item.button?.highlight(false)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isShown else { return }
            self.panel.orderOut(nil)
        })
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: StatusController?

    func applicationDidFinishLaunching(_ n: Notification) {
        _ = Model.shared
        status = StatusController()
    }
    func applicationWillTerminate(_ n: Notification) {
        Gamma.reset()
    }
}

@main
enum Main {
    static let delegate = AppDelegate()
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
