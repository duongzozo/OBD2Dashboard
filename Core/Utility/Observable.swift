import Foundation

/// Minimal closure-based observable box. The project targets iOS 12, so
/// Combine (iOS 13+) is unavailable — this is the MVVM binding primitive
/// used throughout ViewModels instead.
///
/// Observers are held in a list, not a single slot. An earlier version
/// stored one closure and overwrote it on every `observe` call, which
/// silently killed every registration but the last — `BluetoothManager
/// .connectionState` alone has three subscribers (`OBDEngine`,
/// `TelemetryHub`, `ConnectionViewController`), so two of them were dead
/// at any moment and which one survived depended on tab-load order.
final class Observable<Value> {
    private var observers: [(Value) -> Void] = []

    var value: Value {
        didSet { notify(value) }
    }

    init(_ value: Value) {
        self.value = value
    }

    /// Registers `handler` and immediately fires it once with the current value.
    func observe(_ handler: @escaping (Value) -> Void) {
        observers.append(handler)
        handler(value)
    }

    private func notify(_ newValue: Value) {
        // Iterate a copy so a handler is free to register another observer
        // while being notified without mutating the array mid-iteration.
        for observer in observers {
            observer(newValue)
        }
    }
}
