import Foundation

/// An allowlisted trace: never accepts account IDs, peripheral IDs, URLs or payload bytes.
@MainActor public final class WaterDiagnostics {
    public enum Event: String, Codable, Sendable {
        case startRequested, finishRequested, reviewRequested, sessionSaved, authorizationReply, stateReply
        case finishBlocked, closeRequested, operationFailed, bluetoothStep, bluetoothWrite, bluetoothReply, disconnected, connectionLost
    }
    public enum Step: String, Codable, Sendable {
        case power, connect, service, characteristics, subscribe, exchange, disconnect
    }
    public enum FrameKind: String, Codable, Sendable { case identity, authorization, active, other }
    public enum Command: String, Codable, Sendable { case identity, authorization, close, other }
    public struct Entry: Codable, Equatable, Sendable {
        public let time: Date
        public let event: Event
        public let stage: SessionStage?
        public let step: Step?
        public let frameKind: FrameKind?
        public let byteCount: Int?
        public let error: String?
        public let command: Command?
    }
    public private(set) var entries: [Entry]
    private let save: (([Entry]) -> Void)?
    public init(entries: [Entry] = [], save: (([Entry]) -> Void)? = nil) {
        self.entries = Array(entries.suffix(200)); self.save = save
    }
    public func record(_ event: Event, stage: SessionStage? = nil, step: Step? = nil,
                       frame: Data? = nil, error: WaterError? = nil, command: Command? = nil) {
        let kind: FrameKind? = frame.map {
            switch ($0.first, $0.count) {
            case (0x55, 20): return .identity
            case (0xAA, 9): return .authorization
            case (0xA5, 1): return .active
            default: return .other
            }
        }
        // Case names, rather than underlying error descriptions or system error userInfo.
        let code = error.map { String(describing: $0) }
        entries.append(Entry(time: Date(), event: event, stage: stage, step: step,
                             frameKind: kind, byteCount: frame.map { min($0.count, 65536) }, error: code, command: command))
        entries = Array(entries.suffix(200)); save?(entries)
    }
}
