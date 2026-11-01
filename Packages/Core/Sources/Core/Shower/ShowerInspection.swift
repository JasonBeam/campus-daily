import Foundation

/// The read-only controller check behind 核对宿舍的水控: connect, ask the identity (`AA`),
/// disconnect. Never sent during a session.
public enum ShowerInspection {
    public enum Outcome: Sendable, Equatable {
        /// The controller answered with this room's machine id.
        case verified(peripheralID: String)
        /// The controller is in use (`A5`): it does not say which machine it is.
        case busy(peripheralID: String)
        case otherMachine
        case unreadable

        /// Only a controller that proved its identity may be remembered for the next start.
        public var peripheralToRemember: String? {
            if case .verified(let id) = self { return id }
            return nil
        }
    }

    /// If the remembered controller answers as another machine, `forget` is called and the
    /// check scans once without it. Errors are the transport's `ShowerDeviceError`s; the link
    /// is closed before returning or throwing.
    public static func run(transport: ShowerTransport, bleName: String, machineID: String, remembered: String?,
                           isolation: isolated (any Actor)? = #isolation,
                           forget: (String) -> Void) async throws -> Outcome {
        var preferred = remembered
        do {
            while true {
                let id = try await transport.connect(bleName: bleName, machineID: machineID, required: nil, preferred: preferred)
                let frame = try await transport.exchange(ShowerFrames.probeCommand)
                await transport.disconnect()
                let check = ShowerFrames.check(frame, machineID: machineID)
                if check == .otherMachine, let current = preferred, id == current {
                    forget(current)
                    preferred = nil
                    continue
                }
                switch check {
                case .verified: return .verified(peripheralID: id)
                case .busy: return .busy(peripheralID: id)
                case .otherMachine: return .otherMachine
                case .unreadable: return .unreadable
                }
            }
        } catch {
            await transport.disconnect()
            throw error
        }
    }
}
