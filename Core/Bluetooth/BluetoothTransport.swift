import Foundation

/// A single discovered candidate device, surfaced to the UI during a scan.
struct DiscoveredPeripheral: Equatable {
    var id: String
    var name: String
    var signalStrength: Int?
}

/// Abstraction over the physical link to an OBD-II adapter. `OBDEngine`
/// talks only to this protocol — it never touches CoreBluetooth or
/// ExternalAccessory directly. That's what lets the transport be swapped
/// (BLE today; Classic-SPP/MFi later, if the adapter turns out to need it)
/// without rewriting the OBD request queue, ELM327 init sequence, or PID
/// decoding above it.
protocol BluetoothTransport: AnyObject {
    var state: Observable<ConnectionState> { get }

    /// Begins scanning for candidate adapters. Must not be called again
    /// while already connected (spec: don't scan continuously once linked).
    func startScan(onDiscovered: @escaping (DiscoveredPeripheral) -> Void)
    func stopScan()

    func connect(to peripheralID: String)
    func disconnect()

    /// Sends raw command bytes (e.g. `"ATZ\r"` as ASCII) to the adapter.
    func send(_ data: Data)

    /// Fired whenever a chunk of data arrives from the adapter. The OBD
    /// request queue is responsible for buffering until a full `>` prompt
    /// is seen — the transport itself does no protocol-level framing.
    var onDataReceived: ((Data) -> Void)? { get set }
}
