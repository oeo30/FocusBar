import SwiftUI
import LaunchAtLogin

enum TBBarIconState {
    case idle, work, shortRest, longRest

    var color: NSColor {
        switch self {
        case .idle: return .clear
        case .work: return .systemRed
        case .shortRest, .longRest: return .systemGreen
        }
    }
}

/// Seconds represented by a full circle (a 60-minute clock face).
private let clockFaceSeconds: TimeInterval = 3600

private let pieSize: CGFloat = 18

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

/// Menu bar image: the pie drawn as a 60-minute clock face.
private func makeBarIcon(state: TBBarIconState, secondsLeft: TimeInterval) -> NSImage {
    let image = NSImage(size: NSSize(width: pieSize, height: pieSize), flipped: false) { rect in
        drawPie(in: rect, state: state, secondsLeft: secondsLeft, outlined: true)
        return true
    }
    image.isTemplate = false
    return image
}

private let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)

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

class TBStatusItem: NSObject, NSApplicationDelegate {
    private var popover = NSPopover()
    private var statusBarItem: NSStatusItem?
    private var iconState: TBBarIconState = .idle
    private var iconSecondsLeft: TimeInterval = 0
    static var shared: TBStatusItem!

    func applicationDidFinishLaunching(_: Notification) {
        let view = TBPopoverView()

        popover.behavior = .transient
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = NSHostingView(rootView: view)
        if let contentViewController = popover.contentViewController {
            popover.contentSize.height = contentViewController.view.intrinsicContentSize.height
            popover.contentSize.width = 240
        }

        statusBarItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        statusBarItem?.button?.imagePosition = .imageLeft
        setIcon(state: .idle)
        statusBarItem?.button?.action = #selector(TBStatusItem.togglePopover(_:))
    }

    func setTitle(title: String?) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 0.9
        paragraphStyle.alignment = NSTextAlignment.center

        let attributedTitle = NSAttributedString(
            string: title != nil ? " \(title!)" : "",
            attributes: [
                NSAttributedString.Key.font: digitFont,
                NSAttributedString.Key.paragraphStyle: paragraphStyle
            ]
        )
        statusBarItem?.button?.attributedTitle = attributedTitle
    }

    func setIcon(state: TBBarIconState, secondsLeft: TimeInterval = 0) {
        iconState = state
        iconSecondsLeft = secondsLeft
        redrawIcon()
    }

    func setProgress(secondsLeft: TimeInterval) {
        iconSecondsLeft = secondsLeft
        redrawIcon()
    }

    private func redrawIcon() {
        statusBarItem?.button?.image = makeBarIcon(state: iconState, secondsLeft: iconSecondsLeft)
    }

    func showPopover(_: AnyObject?) {
        if let button = statusBarItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            popover.contentViewController?.view.window?.makeKey()
        }
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
