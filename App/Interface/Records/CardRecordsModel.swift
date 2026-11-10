import Foundation
import Core

extension CardRecordsSource {
    /// `campus`'s school session (the live one, or a sample's, which reads nothing): pages for
    /// the person signed in when the list was read from today.
    @MainActor static func school(_ campus: CampusModel) -> CardRecordsSource {
        let session = campus.schoolSession
        return CardRecordsSource(stamp:{ await session.personStamp() },
                                 page:{ query, stamp in try await session.cardHistoryPage(query, since:stamp) },
                                 samePerson:{ await session.isSamePerson(since:$0) },
                                 renew:{ [weak campus] in await campus?.renewCardSession() ?? false })
    }
}

/// 校园卡记录's state for SwiftUI, over Core's `CardRecordsLoader`. Nothing is stored: every
/// visit (and every pull) starts from today.
@MainActor final class CardRecordsModel: ObservableObject {
    @Published private(set) var state = CardRecordsState()
    private let loader: CardRecordsLoader

    init(source: CardRecordsSource) {
        loader = CardRecordsLoader(source:source)
        loader.changed = { [weak self] in self?.state = $0 }
    }

    var phase: CardRecordsState.Phase { state.phase }
    var history: CardHistory? { state.history }
    var loadingMore: Bool { state.loadingMore }
    var moreFailed: Bool { state.moreFailed }
    var reloads: Int { state.reloads }

    /// From today again (first visit, pull).
    func reload() async { await loader.reload() }
    /// Older records: when the list's end appears, or 「点这里再试」.
    func loadMore() async { await loader.loadMore() }
}
