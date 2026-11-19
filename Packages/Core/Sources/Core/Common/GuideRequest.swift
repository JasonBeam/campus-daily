import Foundation

/// One presentation of the first-run guide (暖橙's cover, 清爽's checklist sheet), where it was
/// asked to start (`start`; nil: its first page) and the page it is on now (`page`, which the
/// guide reports with `moved(to:)`).
///
/// Several paths ask for it close together: leaving the sample shows the live root again, whose
/// first-run check asks at once, and 去登录 or a login link asks again a moment later. Asked while
/// one is up, the guide is kept (same `id`): replacing it would dismiss the cover or sheet, which
/// marks the setup seen, and present it again. Asked for a page other than the one it is on, it
/// goes there in place (`contentID` changes, so its pages start again from there); asked for its
/// first page (the first-run check), or for the page it is on, nothing changes.
public struct GuideRequest<Start: Equatable>: Identifiable, Equatable {
    /// The presentation: a new id is a new cover or sheet.
    public let id: UUID
    public private(set) var start: Start?
    /// The page shown now: `start` until the guide moves on.
    public private(set) var page: Start?
    private var revision = 0

    /// The guide's content: changes when it is sent to another page in place.
    public var contentID: String { "\(id.uuidString)/\(revision)" }

    public init(start: Start?) {
        id = UUID()
        self.start = start
        page = start
    }

    /// The guide moved to `page` by itself (the person went on, or back); nothing restarts.
    public mutating func moved(to page: Start?) {
        self.page = page
    }

    /// The guide asked for at `start`, with `current` up (nil: none). Nothing up: a new one. Up:
    /// the same one, sent to `start` when that is a page and not the one shown.
    public static func ask(_ start: Start?, over current: GuideRequest?) -> GuideRequest {
        guard var request = current else { return GuideRequest(start: start) }
        guard let start, start != request.page else { return request }
        request.start = start
        request.page = start
        request.revision += 1
        return request
    }
}
