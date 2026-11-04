import Foundation

/// Writes telemetry samples to a CSV file in the given directory. Values are
/// always in the metric units named in the header, so a log stays comparable
/// whatever the display units were at the time.
final class TelemetryCSVLogger {
    enum LoggerError: Error {
        case cannotCreateFile
    }

    private let directory: URL
    private var handle: FileHandle?
    private(set) var currentFile: URL?
    private(set) var sampleCount = 0

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return formatter
    }()

    private static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    init(directory: URL) {
        self.directory = directory
    }

    var isRecording: Bool { handle != nil }

    func start(at date: Date = Date()) throws {
        guard handle == nil else { return }
        let file = directory.appendingPathComponent("obd_log_\(Self.fileNameFormatter.string(from: date)).csv")
        guard FileManager.default.createFile(atPath: file.path, contents: Self.headerLine().data(using: .utf8)) else {
            throw LoggerError.cannotCreateFile
        }
        let newHandle = try FileHandle(forWritingTo: file)
        newHandle.seekToEndOfFile()
        handle = newHandle
        currentFile = file
        sampleCount = 0
    }

    func append(_ snapshot: TelemetrySnapshot, at date: Date = Date()) {
        guard let handle = handle else { return }
        let columns = PIDDisplay.measuredPIDs.map { pid -> String in
            guard let value = snapshot.value(for: pid)?.value else { return "" }
            return String(format: "%.3f", value)
        }
        let line = ([Self.timestampFormatter.string(from: date)] + columns).joined(separator: ",") + "\n"
        if let data = line.data(using: .utf8) {
            handle.write(data)
            sampleCount += 1
        }
    }

    /// Returns the finished file. `currentFile` stays set so it can still be shared.
    @discardableResult
    func stop() -> URL? {
        handle?.closeFile()
        handle = nil
        return currentFile
    }

    private static func headerLine() -> String {
        let columns = PIDDisplay.measuredPIDs.map { pid -> String in
            let unit = PIDDisplay.metricUnit(for: pid)
            return "\"\(pid.displayName) (\(unit))\""
        }
        return (["timestamp"] + columns).joined(separator: ",") + "\n"
    }
}
