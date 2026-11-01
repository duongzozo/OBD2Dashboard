import Foundation

/// Minimal closure-based observable box. The project targets iOS 12, so
/// Combine (iOS 13+) is unavailable — this is the MVVM binding primitive
/// used throughout ViewModels instead.
final class Observable<Value> {
    private var observer: ((Value) -> Void)?

    var value: Value {
        didSet { observer?(value) }
    }

    init(_ value: Value) {
        self.value = value
    }

    /// Registers `handler` and immediately fires it once with the current value.
    func observe(_ handler: @escaping (Value) -> Void) {
        observer = handler
        handler(value)
    }
}
