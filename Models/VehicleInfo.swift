import Foundation

/// What the adapter and vehicle report about themselves. Every field is
/// optional: older vehicles may not answer the VIN request at all.
struct VehicleInfo: Equatable {
    var adapterVersion: String?
    var protocolName: String?
    var vin: String?

    static let unknown = VehicleInfo()
}
