import Foundation
import SwiftUI

protocol TBLogEvent: Encodable {
    var type: String { get }
    var timestamp: Date { get }
}

class TBLogEventAppStart: TBLogEvent {
    internal let type = "appstart"
    internal let timestamp: Date = Date()
}

class TBLogEventTransition: TBLogEvent {
    internal let type = "transition"
    internal let timestamp: Date = Date()

    private let event: String
    private let fromState: String
    private let toState: String

    init(fromContext ctx: TBStateMachine.Context) {
        event = "\(ctx.event!)"
        fromState = "\(ctx.fromState)"
        toState = "\(ctx.toState)"
    }
}

private let logFileName = "TomatoBar.log"
private let lineEnd = "\n".data(using: .utf8)!

/// Application Support/TomatoBar/TomatoBar.log. Older versions kept the log in Caches,
/// which the system may purge, so an existing cache file is moved over once.
private func logFileURL() -> URL {
    let fileManager = FileManager.default
    let dir = fileManager
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent("TomatoBar", isDirectory: true)
    try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(logFileName)

    let legacy = fileManager
        .urls(for: .cachesDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent(logFileName)
    if !fileManager.fileExists(atPath: url.path), fileManager.fileExists(atPath: legacy.path) {
        try? fileManager.moveItem(at: legacy, to: url)
    }
    return url
}

internal let logger = TBLogger()

class TBLogger {
    private let logHandle: FileHandle?
    private let encoder = JSONEncoder()
    let fileURL = logFileURL()

    init() {
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .secondsSince1970

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: fileURL.path) {
            guard fileManager.createFile(atPath: fileURL.path, contents: nil) else {
                print("cannot create log file")
                logHandle = nil
                return
            }
        }

        logHandle = FileHandle(forUpdatingAtPath: fileURL.path)
        guard logHandle != nil else {
            print("cannot open log file")
            return
        }
    }

    func append(event: TBLogEvent) {
        guard let logHandle = logHandle else {
            return
        }
        do {
            let jsonData = try encoder.encode(event)
            try logHandle.seekToEnd()
            try logHandle.write(contentsOf: jsonData + lineEnd)
            try logHandle.synchronize()
        } catch {
            print("cannot write to log file: \(error)")
        }
    }
}

// MARK: - History built from the log

struct TBSession: Identifiable {
    let id: Date
    let mode: TBMode
    let start: Date
    let end: Date
    let ongoing: Bool

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Hour at which a new day starts for the history: 06:00 to 05:59 the next morning.
private let dayStartHour = 6
/// Sessions shorter than this are not shown or counted.
private let minimumSessionLength: TimeInterval = 5 * 60

/// Study/rest sessions reconstructed from the transition log.
class TBHistory: ObservableObject {
    @Published private(set) var todaySessions: [TBSession] = []
    @Published private(set) var todayStudySeconds: TimeInterval = 0

    private struct Entry: Decodable {
        let type: String
        let timestamp: Date
        let fromState: String?
        let toState: String?
    }

    func reload() {
        let dayStart = Self.currentDayStart()
        let today = parseSessions().filter { $0.start >= dayStart && $0.duration >= minimumSessionLength }
        todaySessions = today.reversed()
        todayStudySeconds = today.filter { $0.mode == .work }.reduce(0) { $0 + $1.duration }
    }

    /// The most recent 06:00 at or before now.
    private static func currentDayStart(now: Date = Date()) -> Date {
        let calendar = Calendar.current
        var start = calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: now)!
        if start > now {
            start = calendar.date(byAdding: .day, value: -1, to: start)!
        }
        return start
    }

    private func parseSessions() -> [TBSession] {
        guard let data = try? Data(contentsOf: logger.fileURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        var sessions: [TBSession] = []
        var open: (mode: TBMode, start: Date)?
        for line in text.split(separator: "\n") {
            guard let entry = try? decoder.decode(Entry.self, from: Data(line.utf8)) else { continue }
            if entry.type == "appstart" {
                // The app was relaunched: whatever was running ended without a transition.
                open = nil
                continue
            }
            guard entry.type == "transition" else { continue }
            if let current = open {
                sessions.append(TBSession(id: current.start, mode: current.mode,
                                          start: current.start, end: entry.timestamp, ongoing: false))
                open = nil
            }
            switch entry.toState {
            case "work": open = (.work, entry.timestamp)
            case "rest": open = (.rest, entry.timestamp)
            default: break
            }
        }
        if let current = open {
            sessions.append(TBSession(id: current.start, mode: current.mode,
                                      start: current.start, end: Date(), ongoing: true))
        }
        return sessions
    }
}
