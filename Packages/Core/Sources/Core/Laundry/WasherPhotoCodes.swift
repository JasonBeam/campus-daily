import Foundation

/// The QR codes found in a photo picked on the common-washer page.
public enum WasherPhotoCodes: Equatable, Sendable {
    case one(String)
    /// No readable code in the photo.
    case none
    /// Different codes: the photo shows more than one machine.
    case several

    /// `payloads`: what the detector read per code (nil = a code it could not read).
    public init(payloads: [String?]) {
        let codes = Set(payloads.compactMap { $0 })
        switch codes.count {
        case 0: self = .none
        case 1: self = .one(codes.first!)
        default: self = .several
        }
    }

    /// What the page shows instead of going on; nil for `.one`.
    public var message: String? {
        switch self {
        case .one: return nil
        case .none: return "照片里没找到二维码，换一张拍清楚的。"
        case .several: return "照片里有好几个码，选一张只拍了一台的。"
        }
    }
}
