import SwiftUI
import LaunchAtLogin

enum TBBarIconState {
    case idle, work, rest

    var color: NSColor {
        switch self {
        case .idle: return .clear
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

    guard state != .idle else { return }
    let fraction = min(max(secondsLeft / clockFaceSeconds, 0), 1)
    guard fraction > 0 else { return }

    let wedge = NSBezierPath()
    wedge.move(to: center)
    wedge.appendArc(withCenter: center, radius: wedgeRadius,
                    startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
    wedge.close()
    state.color.setFill()
    wedge.fill()
}

/// Menu bar image: the tomato logo while idle, the pie alone, or a capsule in the state color
/// wrapping the pie and the time.
private func makeBarIcon(state: TBBarIconState, secondsLeft: TimeInterval, title: String?) -> NSImage {
    if state == .idle, let logo = NSImage(named: "BarIconIdle") {
        return logo
    }
    guard let title = title, !title.isEmpty else {
        let image = NSImage(size: NSSize(width: pieSize, height: pieSize), flipped: false) { rect in
            drawPie(in: rect, state: state, secondsLeft: secondsLeft, outlined: true)
            return true
        }
        image.isTemplate = false
        return image
    }

    let text = NSAttributedString(string: title, attributes: [
        .font: titleFont, .foregroundColor: NSColor.white, .kern: titleKern,
    ])
    let textWidth = text.size().width - titleKern
    let padding: CGFloat = 1.5
    let inner = capsuleHeight - padding * 2
    let gap: CGFloat = 3
    let width = padding + inner + gap + textWidth + 7

    let image = NSImage(size: NSSize(width: width, height: capsuleHeight), flipped: false) { rect in
        let capsule = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        state.color.setFill()
        capsule.fill()

        drawPie(in: NSRect(x: padding, y: padding, width: inner, height: inner),
                state: state, secondsLeft: secondsLeft, outlined: false)

        let baseline = rect.midY - titleFont.capHeight / 2
        text.draw(at: NSPoint(x: padding + inner + gap, y: baseline + titleFont.descender))
        return true
    }
    image.isTemplate = false
    return image
}

@main
struct TBApp: App {
    @NSApplicationDelegateAdaptor(TBStatusItem.self) var appDelegate

    init() {
        TBStatusItem.shared = appDelegate
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

    func setIcon(state: TBBarIconState, secondsLeft: TimeInterval = 0) {
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
        if let button = statusBarItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Resize the popover to fit the active tab.
    func setContentHeight(_ height: CGFloat) {
        guard height > 0, abs(popover.contentSize.height - height) > 0.5 else { return }
        popover.contentSize = NSSize(width: 240, height: height)
    }

    func closePopover(_ sender: AnyObject?) {
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
