import Foundation

/// Lifecycle states of the Bluetooth/ELM327/ECU connection pipeline.
/// Driven by `BLETransport` for the link and `OBDEngine` for the ECU.
enum ConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case initializing
    case ecuReady
    case error(String)

    var shortLabel: String {
        switch self {
        case .disconnected: return "DISCONNECTED"
        case .scanning: return "SCANNING"
        case .connecting: return "CONNECTING"
        case .connected: return "CONNECTED"
        case .initializing: return "INITIALIZING"
        case .ecuReady: return "ECU READY"
        case .error: return "ERROR"
        }
    }
}
