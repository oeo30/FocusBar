import SwiftState
import SwiftUI

/// Which interval the user is editing in the popover, and which one the next start launches.
enum TBMode {
    case work, rest
}

class TBTimer: ObservableObject {
    @AppStorage("showTimerInMenuBar") var showTimerInMenuBar = true
    @AppStorage("workIntervalLength") var workIntervalLength = 25
    @AppStorage("shortRestIntervalLength") var restIntervalLength = 5
    // This preference is "hidden"
    @AppStorage("overrunTimeLimit") var overrunTimeLimit = -60.0

    private var stateMachine = TBStateMachine(state: .idle)
    public let player = TBPlayer()
    private var notificationCenter = TBNotificationCenter()
    private var finishTime: Date!
    private var timerFormatter = DateComponentsFormatter()
    @Published var mode: TBMode = .work
    @Published var timeLeft: TimeInterval = 0
    @Published var timeLeftString: String = ""
    @Published var timer: DispatchSourceTimer?

    var isRunning: Bool { timer != nil }
    var state: TBStateMachineStates { stateMachine.state }

    init() {
        /*
         * State diagram
         *
         * State diagram
         *
         *             start/stop (mode == work)
         *   +--------------------------------+
         *   |                                v
         * +------+   timerFired, start/stop   +------+
         * | idle | <------------------------- | work |
         * +------+                            +------+
         *   |  ^
         *   |  |   timerFired, start/stop     +------+
         *   |  +----------------------------- | rest |
         *   |                                 +------+
         *   +--------------------------------^
         *             start/stop (mode == rest)
         *
         * A finished interval goes back to idle and flips the mode, so the next
         * start is the other kind. Nothing starts without the user.
         */
        stateMachine.addRoutes(event: .startStop, transitions: [.idle => .work]) { _ in
            self.mode == .work
        }
        stateMachine.addRoutes(event: .startStop, transitions: [.idle => .rest]) { _ in
            self.mode == .rest
        }
        stateMachine.addRoutes(event: .startStop, transitions: [.work => .idle, .rest => .idle])
        stateMachine.addRoutes(event: .timerFired, transitions: [.work => .idle, .rest => .idle])

        stateMachine.addAnyHandler(.any => .work, handler: onWorkStart)
        stateMachine.addAnyHandler(.any => .rest, handler: onRestStart)
        stateMachine.addAnyHandler(.any => .idle, handler: onIdleStart)
        stateMachine.addAnyHandler(.any => .any, handler: { ctx in
            logger.append(event: TBLogEventTransition(fromContext: ctx))
        })

        stateMachine.addErrorHandler { ctx in fatalError("state machine context: <\(ctx)>") }

        timerFormatter.unitsStyle = .positional
        timerFormatter.allowedUnits = [.minute, .second]
        timerFormatter.zeroFormattingBehavior = .pad

        notificationCenter.setActionHandler(handler: onNotificationAction)

        let aem: NSAppleEventManager = NSAppleEventManager.shared()
        aem.setEventHandler(self,
                            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
                            forEventClass: AEEventClass(kInternetEventClass),
                            andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor,
                                 withReplyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.forKeyword(AEKeyword(keyDirectObject))?.stringValue else {
            print("url handling error: cannot get url")
            return
        }
        let url = URL(string: urlString)
        guard url != nil,
              let scheme = url!.scheme,
              let host = url!.host else {
            print("url handling error: cannot parse url")
            return
        }
        guard scheme.caseInsensitiveCompare("focustimer") == .orderedSame else {
            print("url handling error: unknown scheme \(scheme)")
            return
        }
        switch host.lowercased() {
        case "startstop":
            startStop()
        default:
            print("url handling error: unknown command \(host)")
            return
        }
    }

    func startStop() {
        stateMachine <-! .startStop
    }

    /// Length in minutes of the interval currently selected by `mode`.
    var selectedLength: Int {
        get { mode == .work ? workIntervalLength : restIntervalLength }
        set {
            // @AppStorage inside an ObservableObject does not publish, so do it by hand.
            objectWillChange.send()
            if mode == .work {
                workIntervalLength = newValue
            } else {
                restIntervalLength = newValue
            }
        }
    }

    func select(mode: TBMode) {
        guard !isRunning else { return }
        self.mode = mode
    }

    func updateTimeLeft() {
        timeLeft = finishTime.timeIntervalSince(Date())
        timeLeftString = timerFormatter.string(from: Date(), to: finishTime)!
        if timer != nil {
            TBStatusItem.shared.update(secondsLeft: timeLeft,
                                       title: showTimerInMenuBar ? timeLeftString : nil)
        }
    }

    private func startTimer(seconds: Int) {
        finishTime = Date().addingTimeInterval(TimeInterval(seconds))

        let queue = DispatchQueue(label: "Timer")
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer!.schedule(deadline: .now(), repeating: .seconds(1), leeway: .never)
        timer!.setEventHandler(handler: onTimerTick)
        timer!.setCancelHandler(handler: onTimerCancel)
        timer!.resume()
    }

    private func stopTimer() {
        timer!.cancel()
        timer = nil
    }

    private func onTimerTick() {
        /* Cannot publish updates from background thread */
        DispatchQueue.main.async { [self] in
            updateTimeLeft()
            let timeLeft = finishTime.timeIntervalSince(Date())
            if timeLeft <= 0 {
                /*
                 Ticks can be missed during the machine sleep.
                 Stop the timer if it goes beyond an overrun time limit.
                 */
                if timeLeft < overrunTimeLimit {
                    stateMachine <-! .startStop
                } else {
                    stateMachine <-! .timerFired
                }
            }
        }
    }

    private func onTimerCancel() {
        DispatchQueue.main.async { [self] in
            updateTimeLeft()
        }
    }

    private func onNotificationAction(action: TBNotification.Action) {
        guard stateMachine.state == .idle else { return }
        mode = action == .startRest ? .rest : .work
        startStop()
    }

    private func onWorkStart(context _: TBStateMachine.Context) {
        mode = .work
        TBStatusItem.shared.setIcon(state: .work, secondsLeft: TimeInterval(workIntervalLength * 60))
        startTimer(seconds: workIntervalLength * 60)
    }

    private func onRestStart(context _: TBStateMachine.Context) {
        mode = .rest
        TBStatusItem.shared.setIcon(state: .rest, secondsLeft: TimeInterval(restIntervalLength * 60))
        startTimer(seconds: restIntervalLength * 60)
    }

    private func onIdleStart(context ctx: TBStateMachine.Context) {
        stopTimer()
        guard ctx.event == .timerFired else {
            TBStatusItem.shared.setIcon(state: .idle)
            return
        }
        // An interval ran to completion: ding, notify, blink the menu bar, and offer the other kind next.
        player.playDing()
        if ctx.fromState == .work {
            mode = .rest
            notificationCenter.send(
                title: NSLocalizedString("TBTimer.workFinished.title", comment: "Study finished title"),
                body: NSLocalizedString("TBTimer.workFinished.body", comment: "Study finished body"),
                category: .workFinished
            )
        } else {
            mode = .work
            notificationCenter.send(
                title: NSLocalizedString("TBTimer.restFinished.title", comment: "Rest finished title"),
                body: NSLocalizedString("TBTimer.restFinished.body", comment: "Rest finished body"),
                category: .restFinished
            )
        }
        TBStatusItem.shared.setAttention(state: ctx.fromState == .work ? .work : .rest)
    }
}
