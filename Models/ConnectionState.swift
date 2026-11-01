import Foundation

/// Lifecycle states of the Bluetooth/ELM327/ECU connection pipeline.
/// Real BluetoothTransport + OBDEngine implementations (Phase 2/3) will drive
/// this; the Phase 1 simulator only ever reports `.demoMode`.
enum ConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case initializing
    case ecuReady
    case error(String)
    case demoMode

    var shortLabel: String {
        switch self {
        case .disconnected: return "DISCONNECTED"
        case .scanning: return "SCANNING"
        case .connecting: return "CONNECTING"
        case .connected: return "CONNECTED"
        case .initializing: return "INITIALIZING"
        case .ecuReady: return "ECU READY"
        case .error: return "ERROR"
        case .demoMode: return "DEMO MODE"
        }
    }
}
