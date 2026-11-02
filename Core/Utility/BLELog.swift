import Foundation

/// In-app ring-buffer log for the Bluetooth stack.
///
/// Why this exists rather than plain `print`/`NSLog` alone: the target
/// device is a jailbroken iPad mini 3 running an AppSync-installed `.ipa`
/// with no Xcode/debugger attached, so console output is effectively
/// unreadable in the field. Every entry therefore goes to *both* `NSLog`
/// (for `idevicesyslog`/Console.app when a Mac happens to be available)
/// and an observable buffer the Connection screen renders on-device.
///
/// `os.Logger` is deliberately not used — it requires iOS 14, and this
/// project's deployment target is iOS 12.
final class BLELog {
    static let shared = BLELog()

    /// Most recent entries, newest last. Always mutated on the main queue
    /// so UI observers never see a torn array.
    let entries: Observable<[String]> = Observable([])

    private let maxEntries = 400
    private let startedAt = Date()

    private init() {}

    func log(_ message: String) {
        // Seconds since launch beats wall-clock here: the interesting
        // question is almost always "how long after init did state change,
        // and did any discovery arrive", not what time of day it was.
        let elapsed = String(format: "%7.3f", Date().timeIntervalSince(startedAt))
        let line = "[\(elapsed)] \(message)"
        NSLog("[BLE] %@", line)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            var current = self.entries.value
            current.append(line)
            if current.count > self.maxEntries {
                current.removeFirst(current.count - self.maxEntries)
            }
            self.entries.value = current
        }
    }

    func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.entries.value = []
        }
    }

    /// Full log as a single blob, for the Connection screen's copy button.
    var plainText: String {
        return entries.value.joined(separator: "\n")
    }
}
