import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

extension KeyboardShortcuts.Name {
    static let startStopTimer = Self("startStopTimer")
}

private let popoverWidth: CGFloat = 240
private let tabContentHeight: CGFloat = 284
private let dialFont = Font.custom("DINCondensed-Bold", size: 12)

extension TBMode {
    var color: Color { Color(self == .work ? TBBarIconState.work.color : TBBarIconState.rest.color) }
    var label: String {
        self == .work
            ? NSLocalizedString("TimerView.work.label", comment: "Study mode label")
            : NSLocalizedString("TimerView.rest.label", comment: "Rest mode label")
    }
}

/// A 60-minute dial: drag the knob to set minutes, or show the remaining fraction while running.
private struct DialView: View {
    @Binding var minutes: Int
    let color: Color
    /// Remaining minutes while the timer runs; nil when idle (dial is editable).
    let remaining: Double?

    private let radius: CGFloat = 76
    private let labelInset: CGFloat = 14
    @State private var lastMinutes = 0

    private var isEditable: Bool { remaining == nil }
    private var shownMinutes: Double { remaining ?? Double(minutes) }
    private var size: CGFloat { (radius + labelInset + 8) * 2 }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.12))
                .frame(width: radius * 2, height: radius * 2)

            Wedge(minutes: shownMinutes)
                .fill(color)
                .frame(width: radius * 2, height: radius * 2)

            ForEach(0 ..< 12) { i in
                let angle = Double(i) * 30 * .pi / 180
                Text("\(i * 5)")
                    .font(dialFont)
                    .foregroundColor(color.opacity(0.8))
                    .offset(x: CGFloat(sin(angle)) * (radius + labelInset),
                            y: -CGFloat(cos(angle)) * (radius + labelInset))
            }

            if isEditable {
                let angle = Double(minutes) * 6 * .pi / 180
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
                    .offset(x: CGFloat(sin(angle)) * radius, y: -CGFloat(cos(angle)) * radius)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .gesture(isEditable ? drag : nil)
        .onAppear { lastMinutes = minutes }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dx = Double(value.location.x - size / 2)
                let dy = Double(value.location.y - size / 2)
                var degrees = atan2(dx, -dy) * 180 / .pi // 0 at 12 o'clock, clockwise
                if degrees < 0 { degrees += 360 }
                var m = Int((degrees / 6).rounded())
                if m == 0 { m = lastMinutes > 30 ? 60 : 1 }
                m = min(max(m, 1), 60)
                if m != minutes {
                    minutes = m
                    lastMinutes = m
                }
            }
    }
}

/// Pie slice from 12 o'clock, clockwise, `minutes` out of 60.
private struct Wedge: Shape {
    var minutes: Double

    var animatableData: Double {
        get { minutes }
        set { minutes = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let fraction = min(max(minutes / 60, 0), 1)
        var path = Path()
        guard fraction > 0 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if fraction >= 1 {
            path.addEllipse(in: rect)
            return path
        }
        path.move(to: center)
        path.addArc(center: center, radius: rect.width / 2,
                    startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
        path.closeSubpath()
        return path
    }
}

private struct ModeToggle: View {
    @EnvironmentObject var timer: TBTimer

    var body: some View {
        HStack(spacing: 0) {
            ForEach([TBMode.work, TBMode.rest], id: \.self) { mode in
                let selected = timer.mode == mode
                Button {
                    timer.select(mode: mode)
                } label: {
                    Text(mode.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(selected ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .background(
                            Capsule().fill(selected ? mode.color : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .frame(width: 120)
        .opacity(timer.isRunning ? 0.6 : 1)
    }
}

private struct TimerView: View {
    @EnvironmentObject var timer: TBTimer

    private var startLabel = NSLocalizedString("TBPopoverView.start.label", comment: "Start label")
    private var stopLabel = NSLocalizedString("TBPopoverView.stop.label", comment: "Stop label")

    private var minutesBinding: Binding<Int> {
        Binding(get: { timer.selectedLength }, set: { timer.selectedLength = $0 })
    }

    var body: some View {
        VStack(spacing: 8) {
            ModeToggle()

            DialView(minutes: minutesBinding,
                     color: timer.mode.color,
                     remaining: timer.isRunning ? timer.timeLeft / 60 : nil)

            Spacer(minLength: 0)

            Button {
                timer.startStop()
            } label: {
                Text(timer.isRunning ? stopLabel : startLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(Capsule().fill(timer.mode.color))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 16)
        }
    }
}

private struct HistoryView: View {
    var body: some View {
        VStack {
            Spacer()
            Text(NSLocalizedString("HistoryView.empty.label", comment: "No history yet"))
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

private struct VolumeSlider: View {
    @Binding var volume: Double

    var body: some View {
        Slider(value: $volume, in: 0...2) {
            Text(String(format: "%.1f", volume))
        }.gesture(TapGesture(count: 2).onEnded({
            volume = 1.0
        }))
    }
}

private struct SettingsView: View {
    @EnvironmentObject var timer: TBTimer
    @EnvironmentObject var player: TBPlayer
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable

    private var soundColumns = [
        GridItem(.flexible()),
        GridItem(.fixed(110))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            KeyboardShortcuts.Recorder(for: .startStopTimer) {
                Text(NSLocalizedString("SettingsView.shortcut.label",
                                       comment: "Shortcut label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle(isOn: $timer.stopAfterBreak) {
                Text(NSLocalizedString("SettingsView.stopAfterBreak.label",
                                       comment: "Stop after break label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
            Toggle(isOn: $timer.showTimerInMenuBar) {
                Text(NSLocalizedString("SettingsView.showTimerInMenuBar.label",
                                       comment: "Show timer in menu bar label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
                .onChange(of: timer.showTimerInMenuBar) { _ in
                    if timer.isRunning { timer.updateTimeLeft() }
                }
            Toggle(isOn: $launchAtLogin.isEnabled) {
                Text(NSLocalizedString("SettingsView.launchAtLogin.label",
                                       comment: "Launch at login label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)

            Divider().padding(.vertical, 2)

            LazyVGrid(columns: soundColumns, alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("SoundsView.isWindupEnabled.label",
                                       comment: "Windup label"))
                VolumeSlider(volume: $player.windupVolume)
                Text(NSLocalizedString("SoundsView.isDingEnabled.label",
                                       comment: "Ding label"))
                VolumeSlider(volume: $player.dingVolume)
                Text(NSLocalizedString("SoundsView.isTickingEnabled.label",
                                       comment: "Ticking label"))
                VolumeSlider(volume: $player.tickingVolume)
            }

            Spacer(minLength: 0)

            Divider().padding(.vertical, 2)

            Button {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel()
            } label: {
                Text(NSLocalizedString("TBPopoverView.about.label",
                                       comment: "About label"))
                Spacer()
                Text("⌘ A").foregroundColor(Color.gray)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("a")
            Button {
                NSApplication.shared.terminate(self)
            } label: {
                Text(NSLocalizedString("TBPopoverView.quit.label",
                                       comment: "Quit label"))
                Spacer()
                Text("⌘ Q").foregroundColor(Color.gray)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 4)
    }
}

private enum ChildView {
    case timer, history, settings
}

struct TBPopoverView: View {
    @ObservedObject var timer = TBTimer()
    @State private var activeChildView = ChildView.timer

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $activeChildView) {
                Text(NSLocalizedString("TBPopoverView.timer.label",
                                       comment: "Timer tab label")).tag(ChildView.timer)
                Text(NSLocalizedString("TBPopoverView.history.label",
                                       comment: "History tab label")).tag(ChildView.history)
                Text(NSLocalizedString("TBPopoverView.settings.label",
                                       comment: "Settings tab label")).tag(ChildView.settings)
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .pickerStyle(.segmented)

            Group {
                switch activeChildView {
                case .timer:
                    TimerView().environmentObject(timer)
                case .history:
                    HistoryView()
                case .settings:
                    SettingsView().environmentObject(timer).environmentObject(timer.player)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: tabContentHeight)
        }
        .padding(12)
        .frame(width: popoverWidth)
    }
}
