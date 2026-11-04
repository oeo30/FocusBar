import SwiftUI
import LaunchAtLogin

enum TBBarIconState {
    case idle, work, rest

    var color: NSColor {
        switch self {
        case .idle: return NSColor(white: 0.2, alpha: 1) // static 45-minute wedge while idle
        case .work: return TBTheme.shared.workColor
        case .rest: return TBTheme.shared.restColor
        }
    }
}

/// User-chosen colors for study and rest, stored as sRGB hex in UserDefaults.
final class TBTheme: ObservableObject {
    static let shared = TBTheme()
    static let defaultWorkColor = NSColor.systemRed
    static let defaultRestColor = NSColor.systemGreen

    @Published var workColor: NSColor {
        didSet { Self.save(workColor, key: "workColor"); TBStatusItem.shared?.redraw() }
    }
    @Published var restColor: NSColor {
        didSet { Self.save(restColor, key: "restColor"); TBStatusItem.shared?.redraw() }
    }

    private init() {
        workColor = Self.load(key: "workColor") ?? Self.defaultWorkColor
        restColor = Self.load(key: "restColor") ?? Self.defaultRestColor
    }

    func color(for mode: TBMode) -> NSColor {
        mode == .work ? workColor : restColor
    }

    func setColor(_ color: NSColor, for mode: TBMode) {
        if mode == .work { workColor = color } else { restColor = color }
    }

    static func hex(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "" }
        return String(format: "#%02X%02X%02X",
                      Int(round(rgb.redComponent * 255)),
                      Int(round(rgb.greenComponent * 255)),
                      Int(round(rgb.blueComponent * 255)))
    }

    private static func save(_ color: NSColor, key: String) {
        UserDefaults.standard.set(hex(color), forKey: key)
    }

    private static func load(key: String) -> NSColor? {
        guard let hex = UserDefaults.standard.string(forKey: key), hex.count == 7,
              let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

/// Seconds represented by a full circle (a 60-minute clock face).
private let clockFaceSeconds: TimeInterval = 3600

private let pieSize: CGFloat = 18
private let capsuleHeight: CGFloat = 21
private let titleKern: CGFloat = 0.5
private let titleFont: NSFont =
    NSFont(name: "DINCondensed-Bold", size: 15.5) ?? NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)

/// Draws a white disc with a colored wedge for the remaining time, like a kitchen timer:
/// the wedge starts at 12 o'clock and extends clockwise by `secondsLeft` on a 60-minute face.
private func drawPie(in rect: NSRect, state: TBBarIconState, secondsLeft: TimeInterval, outlined: Bool) {
    let circle = rect.insetBy(dx: 0.5, dy: 0.5)
    let center = NSPoint(x: circle.midX, y: circle.midY)
    let wedgeRadius = circle.width / 2 - 2.5 // leave a white margin around the wedge

    let disc = NSBezierPath(ovalIn: circle)
    NSColor.white.setFill()
    disc.fill()
    if outlined {
        disc.lineWidth = 0.5
        NSColor.black.withAlphaComponent(0.2).setStroke()
        disc.stroke()
    }

    // Idle shows a pomodoro timer wound to 45 minutes; running shows the time left.
    let fraction = state == .idle ? 0.75 : min(max(secondsLeft / clockFaceSeconds, 0), 1)
    guard fraction > 0 else { return }

    let wedge = NSBezierPath()
    wedge.move(to: center)
    wedge.appendArc(withCenter: center, radius: wedgeRadius,
                    startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
    wedge.close()
    state.color.setFill()
    wedge.fill()
}

/// Menu bar image: a white disc with a gray 45-minute wedge while idle, the pie alone, or a capsule in the state color
/// wrapping the pie and the time.
/// `inverted` swaps the capsule to a white fill with colored text and ring, used for blinking.
private func makeBarIcon(state: TBBarIconState, secondsLeft: TimeInterval, title: String?, inverted: Bool = false) -> NSImage {
    guard let title = title, !title.isEmpty else {
        let image = NSImage(size: NSSize(width: pieSize, height: pieSize), flipped: false) { rect in
            drawPie(in: rect, state: state, secondsLeft: secondsLeft, outlined: true)
            return true
        }
        image.isTemplate = false
        return image
    }

    let text = NSAttributedString(string: title, attributes: [
        .font: titleFont, .foregroundColor: inverted ? state.color : NSColor.white, .kern: titleKern,
    ])
    let textWidth = text.size().width - titleKern
    let padding: CGFloat = 1.5
    let inner = capsuleHeight - padding * 2
    let gap: CGFloat = 3
    let width = padding + inner + gap + textWidth + 7

    let image = NSImage(size: NSSize(width: width, height: capsuleHeight), flipped: false) { rect in
        let capsule = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        if inverted {
            NSColor.white.setFill()
            capsule.fill()
            let ring = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75),
                                    xRadius: rect.height / 2, yRadius: rect.height / 2)
            ring.lineWidth = 1.5
            state.color.setStroke()
            ring.stroke()
            // Solid colored disc in place of the pie.
            let disc = NSBezierPath(ovalIn: NSRect(x: padding + 0.5, y: padding + 0.5, width: inner - 1, height: inner - 1))
            state.color.setFill()
            disc.fill()
        } else {
            state.color.setFill()
            capsule.fill()
            drawPie(in: NSRect(x: padding, y: padding, width: inner, height: inner),
                    state: state, secondsLeft: secondsLeft, outlined: false)
        }

        let baseline = rect.midY - titleFont.capHeight / 2
        text.draw(at: NSPoint(x: padding + inner + gap, y: baseline + titleFont.descender))
        return true
    }
    image.isTemplate = false
    return image
}

/// Settings written while the app was still TomatoBar live under its old bundle id; copy them once.
private func migrateLegacyDefaults() {
    let defaults = UserDefaults.standard
    let marker = "didMigrateTomatoBarDefaults"
    guard !defaults.bool(forKey: marker),
          let legacy = UserDefaults(suiteName: "com.github.ivoronin.TomatoBar") else { return }
    for key in ["workIntervalLength", "shortRestIntervalLength", "showTimerInMenuBar", "dingVolume", "workColor", "restColor"]
        where defaults.object(forKey: key) == nil {
        if let value = legacy.object(forKey: key) {
            defaults.set(value, forKey: key)
        }
    }
    defaults.set(true, forKey: marker)
}

@main
struct TBApp: App {
    @NSApplicationDelegateAdaptor(TBStatusItem.self) var appDelegate

    init() {
        TBStatusItem.shared = appDelegate
        migrateLegacyDefaults()
        LaunchAtLogin.migrateIfNeeded()
        logger.append(event: TBLogEventAppStart())
    }

    var body: some Scene {
        Settings {}
    }
}

/// NSPopover applies vibrancy to its content, which washes out colors; opt out so the popover
/// shows the same study/rest colors as the menu bar.
private final class TBPopoverHostingView<Content: View>: NSHostingView<Content> {
    override var allowsVibrancy: Bool { false }
}

class TBStatusItem: NSObject, NSApplicationDelegate {
    private var popover = NSPopover()
    private var statusBarItem: NSStatusItem?
    private var iconState: TBBarIconState = .idle
    private var iconSecondsLeft: TimeInterval = 0
    private var iconTitle: String?
    static var shared: TBStatusItem!

    func applicationDidFinishLaunching(_: Notification) {
        let view = TBPopoverView()

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = TBPopoverHostingView(rootView: view)
        if let contentViewController = popover.contentViewController {
            popover.contentSize.height = contentViewController.view.intrinsicContentSize.height
            popover.contentSize.width = 240
        }

        statusBarItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        statusBarItem?.button?.imagePosition = .imageOnly
        setIcon(state: .idle)
        statusBarItem?.button?.action = #selector(TBStatusItem.togglePopover(_:))
    }

    // MARK: Attention (blink after an interval ends)

    private var attentionTimer: Timer?
    private var attentionVisible = false

    /// Blink the finished interval's capsule at 00:00, alternating normal and inverted,
    /// until the popover opens or a timer starts.
    func setAttention(state: TBBarIconState) {
        clearAttention()
        iconState = state
        iconSecondsLeft = 0
        iconTitle = "00:00"
        attentionVisible = true
        redrawIcon()
        attentionTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.attentionVisible.toggle()
            self.statusBarItem?.button?.image = makeBarIcon(state: self.iconState, secondsLeft: 0,
                                                            title: self.iconTitle, inverted: !self.attentionVisible)
        }
    }

    private func clearAttention() {
        attentionTimer?.invalidate()
        attentionTimer = nil
    }

    func setIcon(state: TBBarIconState, secondsLeft: TimeInterval = 0) {
        clearAttention()
        iconState = state
        iconSecondsLeft = secondsLeft
        iconTitle = nil
        redrawIcon()
    }

    func update(secondsLeft: TimeInterval, title: String?) {
        iconSecondsLeft = secondsLeft
        iconTitle = title
        redrawIcon()
    }

    func redraw() {
        redrawIcon()
    }

    private func redrawIcon() {
        let image = makeBarIcon(state: iconState, secondsLeft: iconSecondsLeft, title: iconTitle)
        statusBarItem?.button?.image = image
    }

    func showPopover(_: AnyObject?) {
        if attentionTimer != nil {
            setIcon(state: .idle)
        }
        if let button = statusBarItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: Color panel

    private var colorPanelMode: TBMode = .work

    /// Open the system color panel for a study/rest color. The popover is kept open while the
    /// panel is up (it would otherwise close as soon as the panel takes focus).
    /// `anchor` is the color well's frame in the popover's SwiftUI global coordinates; the panel is
    /// placed beside the popover, level with that row.
    func beginColorEditing(for mode: TBMode, anchor: CGRect) {
        colorPanelMode = mode
        popover.behavior = .semitransient
        let panel = NSColorPanel.shared
        if let window = popover.contentViewController?.view.window, let content = window.contentView {
            let flipped = NSRect(x: anchor.minX, y: content.bounds.height - anchor.maxY,
                                 width: anchor.width, height: anchor.height)
            let onScreen = window.convertToScreen(flipped)
            let gap: CGFloat = 8
            var x = window.frame.maxX + gap // right of the popover
            if let screen = window.screen, x + panel.frame.width > screen.visibleFrame.maxX {
                x = window.frame.minX - panel.frame.width - gap // no room: left of the popover
            }
            panel.setFrameTopLeftPoint(NSPoint(x: x, y: onScreen.maxY + 40))
        }
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = TBTheme.shared.color(for: mode)
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        NotificationCenter.default.addObserver(self, selector: #selector(colorPanelClosed(_:)),
                                               name: NSWindow.willCloseNotification, object: panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFront(nil)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        TBTheme.shared.setColor(sender.color, for: colorPanelMode)
    }

    @objc private func colorPanelClosed(_: Notification) {
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: NSColorPanel.shared)
        popover.behavior = .transient
    }

    /// Resize the popover to fit the active tab.
    func setContentHeight(_ height: CGFloat) {
        guard height > 0, abs(popover.contentSize.height - height) > 0.5 else { return }
        popover.contentSize = NSSize(width: 240, height: height)
    }

    func closePopover(_ sender: AnyObject?) {
        if NSColorPanel.sharedColorPanelExists, NSColorPanel.shared.isVisible {
            NSColorPanel.shared.close()
        }
        popover.performClose(sender)
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            closePopover(sender)
        } else {
            showPopover(sender)
        }
    }
}
