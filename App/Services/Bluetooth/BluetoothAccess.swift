import Foundation
@preconcurrency import CoreBluetooth
import Core

/// Whether the app may use Bluetooth, as a start needs to know it before anything connects.
enum BluetoothAuthorization: Equatable, Sendable {
    /// Never asked: the first start explains itself first (`ShowerStartIntent`).
    case notDetermined
    case allowed
    /// Denied or restricted in Settings: only Settings can change it.
    case denied
}

/// Reads the app's Bluetooth authorization without creating a Bluetooth manager (which would
/// show the system alert), and asks for it once when told to.
@MainActor protocol BluetoothAccess: AnyObject {
    var authorization: BluetoothAuthorization { get }
    /// Shows the system alert (the only place besides a connect that creates the manager) and
    /// returns once it was answered, or at once with what is known when the task is cancelled.
    func request() async -> BluetoothAuthorization
}

extension BluetoothAuthorization {
    init(_ value: CBManagerAuthorization) {
        switch value {
        case .notDetermined: self = .notDetermined
        case .allowedAlways: self = .allowed
        case .denied, .restricted: self = .denied
        @unknown default: self = .denied
        }
    }
}

/// The app's radio: `CBManager.authorization` (a class property: no manager, no alert).
@MainActor final class LiveBluetoothAccess: BluetoothAccess {
    private let transport: BluetoothTransport
    init(transport: BluetoothTransport) { self.transport = transport }
    var authorization: BluetoothAuthorization { BluetoothAuthorization(CBManager.authorization) }
    func request() async -> BluetoothAuthorization { BluetoothAuthorization(await transport.requestAccess()) }
}

/// Services without a radio (the sample's, tests' scripted controllers): nothing to ask.
@MainActor final class AllowedBluetoothAccess: BluetoothAccess {
    var authorization: BluetoothAuthorization { .allowed }
    func request() async -> BluetoothAuthorization { .allowed }
}

enum BluetoothAccessFor {
    @MainActor static func transport(_ transport: any ShowerTransport) -> BluetoothAccess {
        if let radio = transport as? BluetoothTransport { return LiveBluetoothAccess(transport:radio) }
        return AllowedBluetoothAccess()
    }
}
